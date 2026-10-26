;;; org-truss-export-test.el --- Tests for org-truss-export  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -l test/org-truss-core-test.el \
;;       -l test/org-truss-export-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss-export)
(require 'org-truss-core-test)

(defun org-truss-test--render (text)
  (org-truss-test--with text
    (org-truss-render-document (org-truss-read))))

(ert-deftest org-truss-test-render-what-the-reader-sees ()
  "A member is written as its heading, and the text under it after; a
comment, :noexport: and unplaced members stay behind."
  (let ((out (org-truss-test--render org-truss-test--file)))
    (should (string-match-p "^#\\+title: Fortnightly reviews$" out))
    (should (string-match-p "^- Reviews run long\n\n  Reviews ran past the hour" out))
    (should (string-match-p "^  - Some items are urgent\n\n    Some items cannot wait two weeks\\.\n\n    - Urgent items go to chat\n    - Who decides what is urgent$" out))
    (should-not (string-match-p "e\\.x" out))
    (should-not (string-match-p "Robin" out))
    (should-not (string-match-p "Agenda diff" out))
    (should-not (string-match-p "Lone remark" out))
    (should-not (string-match-p "^\\*+ Half the items repeat" out))))

(ert-deftest org-truss-test-render-items ()
  "Members written as items of a list are told as the headings under a
member are, where the list stands in its text: in its list, each opened
with its role where the pattern names it, its text inside, its id and the
list's marks left out, a link pointing to one as its words.  The text
after the list comes after it, and the headings under the member last."
  (let ((out (org-truss-test--render org-truss-test--items-file)))
    (should (string-match-p
             (concat "^- We move to fortnightly reviews\n\n"
                     "  We would meet half as often\\.\n\n"
                     "  - Pros: Less time in meetings\n\n"
                     "    An hour a fortnight back\\.\n"
                     "  - Cons: Items wait longer\n\n"
                     "    1\\. Ask the leads\n"
                     "    2\\. Ask the team\n"
                     "  - 人 :: Robin likes it, as Less time in meetings says\n\n"
                     "  After the list\\.\n\n"
                     "  - A heading under it too\n")
             out))
    (should-not (string-match-p "attr_truss\\|<<\\|\\[\\[" out))))

(ert-deftest org-truss-test-render-items-then-headings ()
  "A tagged end member, a heading after the items, goes on their list where
no text follows it: one list, numbered on.  A heading under a pattern of
one role plays it with none written, as an item does."
  (let ((out (org-truss-test--render "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Check
:PROPERTIES:
:CUSTOM_ID: m1
:TRUSS_BREAKDOWN: steps
:END:
#+attr_truss:
1. Meet the driver
2. Read the checker
*** Write it down                                              :assumption:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
[[truss-include:m1]]
")))
    (should (string-match-p "^1\\. Meet the driver\n2\\. Read the checker\n3\\. Write it down$" out))))

(ert-deftest org-truss-test-render-section-items ()
  "Sections written as items of a list in the structure's text are told as
its headings are: a heading each, its text and what it tells under it."
  (let ((out (org-truss-test--render org-truss-test--part-items-file)))
    (should (string-match-p
             (concat "^We propose a change\\.\n\n"
                     "\\* Where we are\n\n"
                     "- Reviews take an hour\n\n"
                     "\\* Why change\n\n"
                     "\\* We move to fortnightly reviews\n\n"
                     "- Reviews run long\n\n"
                     "\\* Next")
             out))
    (should-not (string-match-p "attr_truss\\|<<\\|\\[\\[\\|sky ::" out))))

(ert-deftest org-truss-test-render-text-after-sections ()
  "Text after a list of sections, which Org cannot put after headings, is
told after them with the sections as a list; text between two lists
stays between them."
  (let ((out (org-truss-test--render
              (replace-regexp-in-string
               "- umbrella :: \\[\\[truss-include:m1\\]\\]\n"
               "- umbrella :: [[truss-include:m1]]\nSo we change.\n#+attr_truss:\n- Last\n"
               org-truss-test--part-items-file t t))))
    (should (string-match-p
             (concat "^We propose a change\\.\n\n"
                     "- Where we are\n\n"
                     "  - Reviews take an hour\n"
                     "- Why change\n"
                     "- We move to fortnightly reviews\n\n"
                     "  - Reviews run long\n\n"
                     "So we change\\.\n\n"
                     "\\* Last\n\n"
                     "\\* Next")
             out))))

(ert-deftest org-truss-test-render-conditions ()
  "A member written under a field of the subject is written where it is placed,
and the field's own text is not."
  (let ((out (org-truss-test--render org-truss-test--conditions-file)))
    (should (string-match-p "^\\* Constraints\n\n- No budget this year$" out))
    (should-not (string-match-p "Finance\\|schedule" out))))

(ert-deftest org-truss-test-render-subject-like-members ()
  "A member of the subject is written as one of the members is, where it is
placed: in the words of the link, then what is nested under it."
  (let ((out (org-truss-test--render org-truss-test--clusters-file)))
    (should (string-match-p (concat "^\\* Background\n\n- The manager checks every driver before and after driving\n\n"
                                    "  The rules ask for a check before and after driving\\.\n\n"
                                    "  - The rule asks for a check before driving\n"
                                    "  - The rule asks for a check after driving\n"
                                    "  - The check may be made by video\n\n\\* What we do")
                            out))
    (should (string-match-p "1\\. The driver blows into the tester" out))))

(ert-deftest org-truss-test-render-titles ()
  "A section is titled by its heading.  A member's heading opens it where
it is told, its text following."
  (dolist (org-truss-language '(en ja))
    (let ((out (org-truss-test--render org-truss-test--file)))
      (should (string-match-p "^\\* Sky$" out))
      (should (string-match-p "^\\* Rain$" out))
      (should (string-match-p "^\\* Umbrella$" out))
      (should (string-match-p "^- Half the items repeat\n\n  Half of each agenda" out)))))

(ert-deftest org-truss-test-render-broken-link ()
  "A link that tells no member shows in the document, where it will be seen."
  (let ((org-truss-language 'en))
    (should (string-match-p "(broken link: truss-include:none)"
                            (org-truss-test--render org-truss-test--file)))))

(ert-deftest org-truss-test-render-lead ()
  "The structure's lead opens the document, before the members it tells."
  (let ((out (org-truss-test--render
              (replace-regexp-in-string
               (regexp-quote ":TRUSS_TELLING: sky-rain-umbrella\n:END:\n")
               ":TRUSS_TELLING: sky-rain-umbrella\n:END:\nRead this first.\n# Not this.\n"
               org-truss-test--file t t))))
    (should (string-match-p "toc:nil num:nil\n\nRead this first\\.\n\n\\* Sky\n\n- Reviews run long" out))))

(ert-deftest org-truss-test-render-document-title ()
  "The file's #+title is the title the document is written under: the
structure's heading names a part."
  (should (string-match-p "\\`#\\+title: Fortnightly reviews\n"
                          (org-truss-test--render org-truss-test--file))))

(ert-deftest org-truss-test-render-includes ()
  "A link that tells a member in text is the member's words where it
stands, its description when it has one, in a sentence too; what follows
them -- its body, then what is under it -- comes after the paragraph or
inside the list item, as a list.  A link on a list item's line of its
own is that item's words.  A link that points to a member reads
as its description, or the member's heading, and is no link in the
document.  Told again inside what it tells, a member would never end:
there the document says so."
  (let* ((org-truss-language 'en)
         (out (org-truss-test--render "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Reviews run long
:PROPERTIES:
:CUSTOM_ID: long
:END:
*** Eight of twelve ran over
** Move to fortnightly
:PROPERTIES:
:CUSTOM_ID: move
:END:
We move, as [[#long]] and [[#long][the calendar]] show:
[[truss-include:long]]
- [[truss-include:loop]]
** Loops back
:PROPERTIES:
:CUSTOM_ID: loop
:END:
[[truss-include:move]]
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[truss-include:move]]
** Then
In short, [[truss-include:long][the long reviews]] end.
")))
    (should (string-match-p
             (concat "^\\* Now\n\n"
                     "- Move to fortnightly\n\n"
                     "  We move, as Reviews run long and the calendar show:\n"
                     "  Reviews run long\n\n"
                     "  - Eight of twelve ran over\n"
                     "  - Loops back\n\n"
                     "    (included without end: truss-include:move)\n\n"
                     "\\* Then\n\n"
                     "In short, the long reviews end\\.\n\n"
                     "- Eight of twelve ran over\n")
             out))
    (should-not (string-match-p "\\[\\[" out))))

(ert-deftest org-truss-test-render-told-on-a-heading ()
  "A link on a heading's line tells there a heading of the document: the
member's words, then what is under it, under headings a level down, in
the order of the file among the sections, its text under its heading.
Below the sixth level, what is under a heading is a list."
  (let ((out (org-truss-test--render "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Meetings run long
:PROPERTIES:
:CUSTOM_ID: long
:END:
*** Eight of twelve ran over
**** By twenty minutes
** Untitled
:PROPERTIES:
:CUSTOM_ID: bare
:END:
Only a body.
*** Under the body
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Sky
*** Where we are
*** [[truss-include:long]]
** Rain
*** [[truss-include:bare]]
** Deep
*** Three
**** Four
***** Five
****** [[truss-include:long]]
")))
    (should (string-match-p
             (concat "^\\* Sky\n\n\\*\\* Where we are\n\n"
                     "\\*\\* Meetings run long\n\n"
                     "\\*\\*\\* Eight of twelve ran over\n\n"
                     "\\*\\*\\*\\* By twenty minutes\n\n"
                     "\\* Rain\n\n\\*\\* Untitled\n\nOnly a body\\.\n\n\\*\\*\\* Under the body\n")
             out))
    (should (string-match-p
             "^\\*\\*\\*\\*\\* Meetings run long\n\n\\*\\*\\*\\*\\*\\* Eight of twelve ran over\n\n- By twenty minutes\n"
             out))))

(ert-deftest org-truss-test-render-content-as-a-list ()
  "What a heading with a logic holds is its content, a list under the
heading; under a telling alone, what it holds is told as the heading is,
under headings a level down."
  (let ((out (org-truss-test--render "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** We move to fortnightly
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_LOGIC: reasons
:END:
*** Half the items repeat
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
**** Eight of twelve agendas
** How we got here
:PROPERTIES:
:CUSTOM_ID: story
:TRUSS_TELLING: scqa
:END:
*** Reviews are weekly
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** [[truss-include:move]]
** [[truss-include:story]]
")))
    (should (string-match-p
             (concat "^\\* We move to fortnightly\n\n"
                     "- Half the items repeat\n\n"
                     "  - Eight of twelve agendas\n\n"
                     "\\* How we got here\n\n"
                     "\\*\\* Reviews are weekly\n")
             out))))

(ert-deftest org-truss-test-render-member-first ()
  "A member comes before what is under it, its title, then its body; with
a telling pattern or none, it is told the same."
  (let* ((text (concat "* M\n:PROPERTIES:\n:TRUSS_PART: message\n:END:\n"
                       "** Claim\n:PROPERTIES:\n:CUSTOM_ID: claim\n:TRUSS_TELLING: prep\n:END:\n"
                       "Claim body.\n"
                       "*** Doubt\n"
                       "*** Ground\n# [[https://e.x/s][s]]\n"
                       "* S\n:PROPERTIES:\n:TRUSS_PART: structure\n:END:\n** Only\n- [[truss-include:claim]]\n"))
         (out (org-truss-test--render text)))
    (should (string-match-p "^- Claim\n\n  Claim body\\.\n\n  - Doubt\n  - Ground\n" out))
    (should (equal (org-truss-test--render (replace-regexp-in-string ":TRUSS_TELLING: prep\n" "" text))
                   out))))

(ert-deftest org-truss-test-render-nesting ()
  "Nested sections are written one level deeper; a titled member told by a
line in a section is no heading, but an item of a list."
  (let ((out (org-truss-test--render "#+title: T
* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Inner title
:PROPERTIES:
:CUSTOM_ID: inner
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** What to do
:PROPERTIES:
:TRUSS_TELLING_ROLE: conclusion
:END:
*** Where we are
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
- [[truss-include:inner]]
")))
    (should (string-match-p "^\\* What to do\n" out))
    (should (string-match-p "^\\*\\* Where we are\n" out))
    (should (string-match-p "^- Inner title$" out))
    (should-not (string-match-p "^\\*+ Inner title" out))))

(ert-deftest org-truss-test-render-steps ()
  "Steps are written as a numbered list, closing over one left out.  What is
nested under a step goes inside its item.  The member comes before them,
whatever its telling pattern."
  (let ((out (org-truss-test--render org-truss-test--steps-file)))
    (should (string-match-p
             (concat "^\\* Do\n\n"
                     "- Check before every test\n\n"
                     "  1\\. Meet the driver face to face\n\n"
                     "     - A video call counts as face to face\n"
                     "  2\\. Breathe into the checker\n\n"
                     "     The driver breathes into the checker\\.\n"
                     "  3\\. Check the checker works\n")
             out))
    (should-not (string-match-p "Note the reading" out)))
  (let ((out (org-truss-test--render
              (replace-regexp-in-string ":TRUSS_BREAKDOWN: steps\n:END:\n# \\[\\[#law"
                                        ":TRUSS_BREAKDOWN: steps\n:TRUSS_TELLING: scqa\n:END:\n# [[#law"
                                        org-truss-test--steps-file))))
    (should (string-match-p "^- Check before every test\n\n  1\\. Meet" out))))

(ert-deftest org-truss-test-render-parts-and-prep ()
  "A breakdown with no reasons is a bulleted list in the order of the file,
each part of one of more than one role opening with its role, and what a
part holds goes inside it.
PREP's places are told as the file has them, after the member: its point
and its point again are headings of their own, and none is written here."
  (let ((out (org-truss-test--render org-truss-test--how-file)))
    (should (string-match-p
             (concat "^- Check before every test\n\n"
                     "  - Who: The driver's manager\n"
                     "  - Where: In the office or by video call\n"
                     "  - When: Before the first run of the day\n"
                     "  - How: As follows\n\n"
                     "    1\\. Meet the driver\n"
                     "    2\\. Read the checker\n"
                     "- What a check needs\n\n"
                     "  - A checker that works\n"
                     "  - Someone to check\n"
                     "- Tests are safer checked\n\n"
                     "  - A drunk driver crashed last year\n"
                     "  - Alcohol slows reactions\n\\'")
             out)))
  (let* ((org-truss-language 'ja)
         (out (org-truss-test--render
               (replace-regexp-in-string
                ":TRUSS_BREAKDOWN: 5w1h" ":TRUSS_BREAKDOWN: 6w1h"
                (replace-regexp-in-string
                 "^\\*\\*\\* Before the first run"
                 "*** Whoever drives\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: whom\n:END:\n*** Before the first run"
                 org-truss-test--how-file)))))
    (should (string-match-p (concat "^  - 誰が：The driver's manager\n  - どこで：In the office or by video call\n"
                                    "  - 誰に：Whoever drives\n  - いつ：")
                            out))))

(ert-deftest org-truss-test-render-a-breakdown-of-reasons ()
  "Reasons broken down are written out as the breakdown says, a list, with
reasons as without; each opens with the role it plays, so the reader is
told which part of the breakdown each is.  What plays none is told as
written."
  (let ((text "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** We move to fortnightly reviews
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_LOGIC: reasons
:TRUSS_BREAKDOWN: pros-cons
:END:
*** Less time in meetings
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: pros
:END:
*** Slower answers
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: cons
:END:
Some items wait a week more.
*** Robin likes it
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
- [[truss-include:move]]
"))
    (should (string-match-p
             (concat "^- We move to fortnightly reviews\n\n"
                     "  - Pros: Less time in meetings\n"
                     "  - Cons: Slower answers\n\n    Some items wait a week more\\.\n"
                     "  - Robin likes it\n")
             (org-truss-test--render text)))
    (let ((org-truss-language 'ja))
      (should (string-match-p "^  - メリット：Less time in meetings$" (org-truss-test--render text))))))

(ert-deftest org-truss-test-render-leaves-out-noexport-sections ()
  "A section tagged :noexport: is left out, with what is under it, whether
it would be a heading or an item of a list."
  (dolist (pattern '("" ":TRUSS_BREAKDOWN: parts\n"))
    (let ((out (org-truss-test--render (concat "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Kept
:PROPERTIES:
:CUSTOM_ID: kept
:END:
** Hidden away
:PROPERTIES:
:CUSTOM_ID: away
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
" pattern ":END:
** Shown
- [[truss-include:kept]]
** Not shown                                                       :noexport:
- [[truss-include:away]]
*** Below it
- [[truss-include:away]]
"))))
      (should (string-match-p "Shown" out))
      (should (string-match-p "Kept" out))
      (should-not (string-match-p "Not shown\\|Below it\\|Hidden away" out)))))

(ert-deftest org-truss-test-render-sections-broken-down ()
  "The sections below one broken down are written out as a list, as the
members under a member are: each an item, not a heading, opened with its
number or role, its title and lead, and inside it the members it lists
and the sections below it, items of a list again."
  (let* ((org-truss-language 'en)
         (file "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Agree next week
:PROPERTIES:
:CUSTOM_ID: agree
:TRUSS_BREAKDOWN: parts
:END:
*** Ask the leads
*** Ask the team
** Change the calendar
:PROPERTIES:
:CUSTOM_ID: cal
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_BREAKDOWN: steps
:END:
** Agree
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
We agree first.
- [[truss-include:agree]]
*** A detail
- [[truss-include:cal]]
** Then
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
- [[truss-include:cal]]
")
         (out (org-truss-test--render file)))
    (should (string-match-p
             (concat "^1\\. Agree\n\n   We agree first\\.\n"
                     "   - Agree next week\n\n"
                     "     - Ask the leads\n     - Ask the team\n\n"
                     "   - A detail\n\n"
                     "     - Change the calendar\n"
                     "2\\. Then\n\n   - Change the calendar\n")
             out))
    (should-not (string-match-p "^\\*+ " out))
    (let ((out (org-truss-test--render
                (replace-regexp-in-string ":TRUSS_BREAKDOWN: steps" ":TRUSS_BREAKDOWN: 5w1h"
                                          (replace-regexp-in-string "ROLE: step" "ROLE: who" file)))))
      (should (string-match-p "^- Who: Agree\n" out)))))

(ert-deftest org-truss-test-render-a-telling-on-a-member ()
  "A member is told before what is under it, and that in the order of the
file, whatever its telling pattern: SCQA's answer, too, is a heading under
it.  What comes below one the pattern tells after it is out of order, for
the file to be put right."
  (dolist (pattern '("scqa" "sds"))
    (let ((out (org-truss-test--render
                (replace-regexp-in-string "scqa" pattern org-truss-test--telling-text))))
      (should (string-match-p
               (concat "^- We move to fortnightly reviews\n\n  From next month\\.\n\n"
                       "  - Should we keep meeting weekly\n  - Half the items repeat\n  - Robin agrees\n"
                       "  - Reviews are weekly\n\\'")
               out))))
  (org-truss-test--with org-truss-test--telling-text
    (let ((model (org-truss-read)))
      (should (equal (mapcar (lambda (o) (org-truss-member-words (car o)))
                             (plist-get (org-truss-checks model) :out-of-order))
                     '("Half the items repeat" "Reviews are weekly")))
      (should (equal (org-truss-gaps (org-truss-test--m model "We move to fortnightly reviews"))
                     '((telling answer . 1)))))))

(ert-deftest org-truss-test-export-writes-files ()
  "The Org file is always written; the Markdown one when pandoc is there."
  (let* ((dir (make-temp-file "org-truss-test" t))
         (file (expand-file-name "truss.org" dir)))
    (unwind-protect
        (progn
          (with-temp-file file (insert org-truss-test--file))
          (let* ((buffer (find-file-noselect file))
                 (org-truss-pandoc-program "no-such-pandoc-org-truss")
                 (written (org-truss-export-buffer buffer)))
            (should (equal written (list (expand-file-name "out/truss.org" dir))))
            (kill-buffer buffer))
          (when (executable-find "pandoc")
            (let* ((buffer (find-file-noselect file))
                   (written (org-truss-export-buffer buffer)))
              (should (equal (length written) 2))
              (with-temp-buffer
                (insert-file-contents (cadr written))
                (should (string-match-p "Reviews ran past the hour" (buffer-string))))
              (kill-buffer buffer))))
      (delete-directory dir t))))

(ert-deftest org-truss-test-export-rebases-file-links ()
  "A link to a file by a relative path is written relative to where the
document goes; its words, a search in the file, and any other link stay."
  (should (equal (org-truss--rebase-file-links
                  (concat "[[file:attach/a b.png]]\n[[./sources/x.pdf][the law]]\n"
                          "[[file:/abs/y.png]] [[https://e.x/z.png]] [[#m7]]\n"
                          "[[file:notes/n.org::*Head]]")
                  "/p/" "/p/out/")
                 (concat "[[file:../attach/a b.png]]\n[[file:../sources/x.pdf][the law]]\n"
                         "[[file:/abs/y.png]] [[https://e.x/z.png]] [[#m7]]\n"
                         "[[file:../notes/n.org::*Head]]"))))

(ert-deftest org-truss-test-export-shows-pictures ()
  "A picture attached to a member and shown in its text is shown in the
document, linked from where the document is written."
  (org-truss-test--in-directory
      (list (cons "attach/ab/cdef/shot.png" "png")
            (cons "truss.org" "# -*- org-attach-id-dir: \"attach/\"; -*-
#+title: T
* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** A claim
:PROPERTIES:
:ID:       abcdef
:CUSTOM_ID: m1
:END:
As the shot shows.

[[attachment:shot.png]]
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[truss-include:m1]]
"))
    (let* ((buffer (find-file-noselect (expand-file-name "truss.org" dir)))
           (written (org-truss-export-buffer buffer)))
      (with-temp-buffer
        (insert-file-contents (car written))
        (should (string-match-p "^ *\\[\\[file:\\.\\./attach/ab/cdef/shot\\.png\\]\\]$"
                                (buffer-string))))
      (when (cdr written)
        (with-temp-buffer
          (insert-file-contents (cadr written))
          (should (string-match-p "!\\[[^]]*\\](\\.\\./attach/ab/cdef/shot\\.png)"
                                  (buffer-string))))))))

(ert-deftest org-truss-test-render-new-file ()
  "A new file is an output document as it stands: the facts told, what
they mean and what to do, each a heading in that order, its words those
of the member Structure includes there.  A compound truss's headings are
headings, a simple truss's items a list."
  (should (string-match-p
           (concat "^\\* Situation\n\n- Part\n\n"
                   "\\* Interpretation\n\n\\*\\* Part\n\n- Reason\n\n"
                   "\\* Action\n\n1\\. Step\n")
           (org-truss-test--render (org-truss-skeleton "T")))))

(ert-deftest org-truss-test-render-compound-as-written ()
  "A compound truss of a listing pattern is written as the file is: its
supporting members written as items a list, those written as headings
headings after it, numbered on where it is numbered.  Under a heading of
a simple truss, a heading is an item."
  (let ((text (org-truss-test--render "#+title: T
* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** Do it
:PROPERTIES:
:CUSTOM_ID: m1
:TRUSS_BREAKDOWN: steps
:END:
#+attr_truss:
1. Book a room
*** Ask them
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:TRUSS_BREAKDOWN: steps
:END:
#+attr_truss:
1. Write
2. Send
** Why
:PROPERTIES:
:CUSTOM_ID: m2
:TRUSS_LOGIC: reasons
:END:
*** It is cheap                                                :assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** [[truss-include:m1]]
** [[truss-include:m2]]
")))
    (should (string-match-p
             (concat "^\\* Do it\n\n1\\. Book a room\n\n\\*\\* 2\\. Ask them\n\n"
                     "1\\. Write\n2\\. Send\n\n\\* Why\n\n- It is cheap\n")
             text))))

(provide 'org-truss-export-test)

;;; org-truss-export-test.el ends here

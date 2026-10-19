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
    (org-truss-render (org-truss-read))))

(ert-deftest org-truss-test-render-what-the-reader-sees ()
  "A public block is written in place of its heading; a member without one is
written as its heading; notes, :noexport: and unplaced members stay behind."
  (let ((out (org-truss-test--render org-truss-test--file)))
    (should (string-match-p "^#\\+title: Fortnightly reviews$" out))
    (should (string-match-p "Reviews ran past the hour" out))
    (should-not (string-match-p "^Reviews run long" out))
    (should (string-match-p "^Some items cannot wait two weeks\\.\n\n- Urgent items go to chat\n- Who decides what is urgent$" out))
    (should-not (string-match-p "Robin" out))
    (should-not (string-match-p "Agenda diff" out))
    (should-not (string-match-p "Lone remark" out))
    (should-not (string-match-p "^\\*+ Half the items repeat" out))))

(ert-deftest org-truss-test-render-conditions ()
  "A member written under a field of the subject is written where it is placed,
and the field's own text is not."
  (let ((out (org-truss-test--render org-truss-test--conditions-file)))
    (should (string-match-p "^\\* Premises\n\nNo budget this year$" out))
    (should-not (string-match-p "Finance\\|schedule" out))))

(ert-deftest org-truss-test-render-subject-like-members ()
  "A member of the subject is written as one of the members is, where it is
placed: in the words of the link, then what is nested under it."
  (let ((out (org-truss-test--render org-truss-test--clusters-file)))
    (should (string-match-p (concat "^\\* Background\n\nThe rules ask for a check before and after driving\\.\n\n"
                                    "The rule asks for a check before driving\n\n"
                                    "The rule asks for a check after driving\n\n"
                                    "The check may be made by video\n\n\\* What we do")
                            out))
    (should (string-match-p "1\\. The driver blows into the tester" out))))

(ert-deftest org-truss-test-render-titles ()
  "A section is titled by its public title, else by its heading.  A
member's public title opens its paragraph in bold."
  (dolist (org-truss-language '(en ja))
    (let ((out (org-truss-test--render org-truss-test--file)))
      (should (string-match-p "^\\* Sky$" out))
      (should (string-match-p "^\\* Why it drags$" out))
      (should (string-match-p "^\\* Umbrella$" out))
      (should (string-match-p "^\\*Most items come back unchanged\\*$" out)))))

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
               ":TRUSS_TELLING: sky-rain-umbrella\n:END:\n#+begin_public\nRead this first.\n#+end_public\n"
               org-truss-test--file t t))))
    (should (string-match-p "toc:nil num:nil\n\nRead this first\\.\n\n\\* Sky\n\nReviews ran past the hour" out))))

(ert-deftest org-truss-test-render-document-title ()
  "The structure's public title, as any section's, is the title the
document is written under; without one, the file's #+title."
  (should (string-match-p "\\`#\\+title: Fortnightly reviews\n"
                          (org-truss-test--render org-truss-test--file)))
  (let ((out (org-truss-test--render
              (replace-regexp-in-string
               (regexp-quote ":TRUSS_TELLING: sky-rain-umbrella\n:END:\n")
               ":TRUSS_TELLING: sky-rain-umbrella\n:END:\n#+begin_public Every other week\nRead this first.\n#+end_public\n"
               org-truss-test--file t t))))
    (should (string-match-p "\\`#\\+title: Every other week\n" out))
    (should (string-match-p "toc:nil num:nil\n\nRead this first\\." out))))

(ert-deftest org-truss-test-render-includes ()
  "A link that tells a member is that member told where it stands, with what
is nested under it: on a line of its own, in a list item, or in a
sentence, inside a public block or not.  Its description names it in the
file alone.  A link that points to a member reads as its description, or
the member's heading, and is no link in the document.  Told again inside
what it tells, a member would never end: there the document says so."
  (let* ((org-truss-language 'en)
         (out (org-truss-test--render "* M
:PROPERTIES:
:TRUSS_PART: members
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
#+begin_public
We move, as [[#long]] and [[#long][the calendar]] show:
[[truss-include:long][named for the file]]
#+end_public
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
- [[truss-include:move][visual]]
")))
    (should (string-match-p
             (concat "^\\* Now\n\n"
                     "We move, as Reviews run long and the calendar show:\n"
                     "Reviews run long\n\nEight of twelve ran over\n\n"
                     "Loops back\n\n"
                     "(told without end: truss-include:move)\n")
             out))
    (should-not (string-match-p "visual\\|named for the file\\|\\[\\[" out))))

(ert-deftest org-truss-test-render-member-first ()
  "A member comes before what is under it, its title in bold; with a
telling pattern or none, it is told the same."
  (let* ((text (concat "* M\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n"
                       "** Claim\n:PROPERTIES:\n:CUSTOM_ID: claim\n:TRUSS_TELLING: prep\n:END:\n"
                       "#+begin_public The claim\nClaim body.\n#+end_public\n"
                       "*** Doubt\n"
                       "*** Ground\n:PROPERTIES:\n:TRUSS_GROUNDS: s\n:END:\n"
                       "* S\n:PROPERTIES:\n:TRUSS_PART: structure\n:END:\n** Only\n- [[truss-include:claim]]\n"))
         (out (org-truss-test--render text)))
    (should (string-match-p "^\\*The claim\\*\nClaim body\\.\n\nDoubt\n\nGround\n" out))
    (should (equal (org-truss-test--render (replace-regexp-in-string ":TRUSS_TELLING: prep\n" "" text))
                   out))))

(ert-deftest org-truss-test-render-nesting ()
  "Nested sections are written one level deeper; a titled member is no
heading, its title opening its paragraph in bold."
  (let ((out (org-truss-test--render "#+title: T
* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Inner claim
:PROPERTIES:
:CUSTOM_ID: inner
:END:
#+begin_public Inner title
#+end_public
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Outer
:PROPERTIES:
:TRUSS_TELLING_ROLE: conclusion
:END:
#+begin_public What to do
#+end_public
*** Inner
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
#+begin_public Where we are
#+end_public
- [[truss-include:inner]]
")))
    (should (string-match-p "^\\* What to do\n" out))
    (should (string-match-p "^\\*\\* Where we are\n" out))
    (should (string-match-p "^\\*Inner title\\*\n" out))
    (should-not (string-match-p "^\\*+ Inner title" out))))

(ert-deftest org-truss-test-render-steps ()
  "Steps are written as a numbered list, closing over one left out.  What is
nested under a step goes inside its item.  The member comes before them,
whatever its telling pattern."
  (let ((out (org-truss-test--render org-truss-test--steps-file)))
    (should (string-match-p
             (concat "^\\* Do\n\n"
                     "Check before every test\n\n"
                     "1\\. Meet the driver face to face\n\n"
                     "   A video call counts as face to face\n"
                     "2\\. The driver breathes into the checker\\.\n"
                     "3\\. Check the checker works\n")
             out))
    (should-not (string-match-p "Note the reading" out)))
  (let ((out (org-truss-test--render
              (replace-regexp-in-string ":TRUSS_BREAKDOWN: steps\n:TRUSS_GROUNDS"
                                        ":TRUSS_BREAKDOWN: steps\n:TRUSS_TELLING: scqa\n:TRUSS_GROUNDS"
                                        org-truss-test--steps-file))))
    (should (string-match-p "^Check before every test\n\n1\\. Meet" out))))

(ert-deftest org-truss-test-render-parts-and-prep ()
  "A breakdown with no reasons is a bulleted list in the order of the file,
each part of one of more than one role opening with its role, and what a
part holds goes inside it.
PREP's places are told as the file has them, after the member: its point
and its point again are headings of their own, and none is written here."
  (let ((out (org-truss-test--render org-truss-test--how-file)))
    (should (string-match-p
             (concat "^Check before every test\n\n"
                     "- Who: The driver's manager\n"
                     "- Where: In the office or by video call\n"
                     "- When: Before the first run of the day\n"
                     "- How: As follows\n\n"
                     "  1\\. Meet the driver\n"
                     "  2\\. Read the checker\n\n"
                     "What a check needs\n\n"
                     "- A checker that works\n"
                     "- Someone to check\n\n"
                     "Tests are safer checked\n\n"
                     "A drunk driver crashed last year\n\n"
                     "Alcohol slows reactions\n\n\\'")
             out)))
  (let* ((org-truss-language 'ja)
         (out (org-truss-test--render
               (replace-regexp-in-string
                ":TRUSS_BREAKDOWN: 5w1h" ":TRUSS_BREAKDOWN: 6w1h"
                (replace-regexp-in-string
                 "^\\*\\*\\* Before the first run"
                 "*** Whoever drives\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: whom\n:END:\n*** Before the first run"
                 org-truss-test--how-file)))))
    (should (string-match-p (concat "^- 誰が：The driver's manager\n- どこで：In the office or by video call\n"
                                    "- 誰に：Whoever drives\n- いつ：")
                            out))))

(ert-deftest org-truss-test-render-a-breakdown-of-reasons ()
  "Reasons broken down are written out as the breakdown says, a list, with
reasons as without; each opens with the role it plays, so the reader is
told which part of the breakdown each is.  What plays none is told as
written."
  (let ((text "* M
:PROPERTIES:
:TRUSS_PART: members
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
*** Items wait longer
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: cons
:END:
#+begin_public Slower answers
Some items wait a week more.
#+end_public
*** Robin likes it
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
- [[truss-include:move]]
"))
    (should (string-match-p
             (concat "^We move to fortnightly reviews\n\n"
                     "- Pros: Less time in meetings\n"
                     "- Cons: Slower answers\n  Some items wait a week more\\.\n"
                     "- Robin likes it\n")
             (org-truss-test--render text)))
    (let ((org-truss-language 'ja))
      (should (string-match-p "^- メリット：Less time in meetings$" (org-truss-test--render text))))))

(ert-deftest org-truss-test-render-leaves-out-noexport-sections ()
  "A section tagged :noexport: is left out, with what is under it, whether
it would be a heading or an item of a list."
  (dolist (pattern '("" ":TRUSS_BREAKDOWN: parts\n"))
    (let ((out (org-truss-test--render (concat "* M
:PROPERTIES:
:TRUSS_PART: members
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
and the sections below it, their titles in bold."
  (let* ((org-truss-language 'en)
         (file "* M
:PROPERTIES:
:TRUSS_PART: members
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
** First
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
#+begin_public Agree
We agree first.
#+end_public
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
             (concat "^1\\. Agree\n   We agree first\\.\n\n"
                     "   Agree next week\n\n"
                     "   - Ask the leads\n   - Ask the team\n\n"
                     "   \\*A detail\\*\n\n"
                     "   Change the calendar\n"
                     "2\\. Then\n\n   Change the calendar\n")
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
               (concat "^\\*Fortnightly\\*\nWe move to fortnightly reviews\\.\n\n"
                       "Should we keep meeting weekly\n\nHalf the items repeat\n\nRobin agrees\n\n"
                       "Reviews are weekly\n\n\\'")
               out))))
  (org-truss-test--with org-truss-test--telling-text
    (let ((model (org-truss-read)))
      (should (equal (mapcar (lambda (o) (org-truss-member-label (car o)))
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
  "A picture attached to a member and shown in its public block is shown in
the document, linked from where the document is written."
  (org-truss-test--in-directory
      (list (cons "attach/ab/cdef/shot.png" "png")
            (cons "truss.org" "# -*- org-attach-id-dir: \"attach/\"; -*-
#+title: T
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim
:PROPERTIES:
:ID:       abcdef
:CUSTOM_ID: m1
:END:
#+begin_public
As the shot shows.

[[attachment:shot.png]]
#+end_public
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
        (should (string-match-p "^\\[\\[file:\\.\\./attach/ab/cdef/shot\\.png\\]\\]$"
                                (buffer-string))))
      (when (cdr written)
        (with-temp-buffer
          (insert-file-contents (cadr written))
          (should (string-match-p "!\\[[^]]*\\](\\.\\./attach/ab/cdef/shot\\.png)"
                                  (buffer-string))))))))

(provide 'org-truss-export-test)

;;; org-truss-export-test.el ends here

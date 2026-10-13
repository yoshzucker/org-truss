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
    (should (string-match-p "^Urgent items go to chat$" out))
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

(ert-deftest org-truss-test-render-subject-cluster ()
  "A summary of the subject is written alone where it is placed: its parts are
the breakdown it was found with, and stay behind."
  (let ((out (org-truss-test--render org-truss-test--clusters-file)))
    (should (string-match-p "^\\* Background\n\nThe rules ask for a check before and after driving\\.\n\n\\* What we do" out))
    (should-not (string-match-p "video\\|rule asks" out))
    (should (string-match-p "1\\. The driver blows into the tester" out))))

(ert-deftest org-truss-test-render-titles ()
  "A section is titled by its public title, else by its heading."
  (dolist (org-truss-language '(en ja))
    (let ((out (org-truss-test--render org-truss-test--file)))
      (should (string-match-p "^\\* Sky$" out))
      (should (string-match-p "^\\* Why it drags$" out))
      (should (string-match-p "^\\* Umbrella$" out))
      (should (string-match-p "^\\*\\* Most items come back unchanged$" out)))))

(ert-deftest org-truss-test-render-wording-and-lead ()
  "A member is told in the words of the link that lists it, in place of its
own; the structure's lead opens the document."
  (let ((out (org-truss-test--render
              (replace-regexp-in-string
               (regexp-quote "- [[#long]]")
               "- [[#long][Our reviews overran eight times.]]"
               (replace-regexp-in-string
                (regexp-quote ":TRUSS_TELLING: sky-rain-umbrella\n:END:\n")
                ":TRUSS_TELLING: sky-rain-umbrella\n:END:\n#+begin_public\nRead this first.\n#+end_public\n"
                org-truss-test--file t t)
               t t))))
    (should (string-match-p "toc:nil num:nil\n\nRead this first\\.\n\n\\* Sky\n\nOur reviews overran eight times\\.$" out))
    (should-not (string-match-p "Reviews ran past the hour" out))))

(ert-deftest org-truss-test-render-broken-link ()
  "A link to no member shows in the document, where it will be seen."
  (let ((org-truss-language 'en))
    (should (string-match-p "(broken link: #none)"
                            (org-truss-test--render org-truss-test--file)))))

(ert-deftest org-truss-test-render-conclusion-last ()
  "A conclusion that comes last follows its support, with its title in bold;
what argues against it still comes after it."
  (let ((out (org-truss-test--render "#+title: T
* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Claim
:PROPERTIES:
:CUSTOM_ID: claim
:TRUSS_TELLING: last
:END:
#+begin_public The claim
Claim body.
#+end_public
*** Ground
:PROPERTIES:
:TRUSS_SOURCE: s
:END:
#+begin_public
Ground body.
#+end_public
*** Doubt                                                           :against:
#+begin_public
Doubt body.
#+end_public
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Only
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
- [[#claim]]
")))
    (should (string-match-p "Ground body\\.\n\n\\*The claim\\*\nClaim body\\.\n\nDoubt body\\." out))
    (should-not (string-match-p "^\\*\\* The claim" out))))

(ert-deftest org-truss-test-render-conclusion-first ()
  "Told conclusion first, a member comes before its support, under a heading
of its own; with no telling pattern it is told the same."
  (let* ((text (concat "* M\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n"
                       "** Claim\n:PROPERTIES:\n:CUSTOM_ID: claim\n:TRUSS_TELLING: first\n:END:\n"
                       "#+begin_public The claim\nClaim body.\n#+end_public\n"
                       "*** Doubt                                                           :against:\n"
                       "*** Ground\n:PROPERTIES:\n:TRUSS_SOURCE: s\n:END:\n"
                       "* S\n:PROPERTIES:\n:TRUSS_PART: structure\n:END:\n** Only\n- [[#claim]]\n"))
         (out (org-truss-test--render text)))
    (should (string-match-p "^\\*\\* The claim\nClaim body\\.\n\nGround\n\nDoubt\n" out))
    (should (equal (org-truss-test--render (replace-regexp-in-string ":TRUSS_TELLING: first\n" "" text))
                   out))))

(ert-deftest org-truss-test-render-nesting ()
  "Nested sections are written one level deeper, titled members deeper still."
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
:TRUSS_ROLE: conclusion
:END:
#+begin_public What to do
#+end_public
*** Inner
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
#+begin_public Where we are
#+end_public
- [[#inner]]
")))
    (should (string-match-p "^\\* What to do\n" out))
    (should (string-match-p "^\\*\\* Where we are\n" out))
    (should (string-match-p "^\\*\\*\\* Inner title\n" out))))

(ert-deftest org-truss-test-render-steps ()
  "Steps are written as a numbered list, closing over one left out.  What is
nested under a step goes inside its item; what argues against the member
follows the list."
  (let ((out (org-truss-test--render org-truss-test--steps-file)))
    (should (string-match-p
             (concat "^\\* Do\n\n"
                     "Check before every test\n\n"
                     "1\\. Meet the driver face to face\n\n"
                     "   A video call counts as face to face\n"
                     "2\\. The driver breathes into the checker\\.\n\n"
                     "The checker may be broken\n")
             out))
    (should-not (string-match-p "Note the reading" out)))
  (let ((out (org-truss-test--render
              (replace-regexp-in-string ":TRUSS_LOGIC: steps\n:TRUSS_GROUNDS"
                                        ":TRUSS_LOGIC: steps\n:TRUSS_TELLING: last\n:TRUSS_GROUNDS"
                                        org-truss-test--steps-file))))
    (should (string-match-p "^1\\. Meet[^\0]*\n\nCheck before every test\n\nThe checker" out))))

(ert-deftest org-truss-test-render-parts-and-prep ()
  "Parts are a bulleted list, those covering aspects opening with the aspect
in the order of the aspects, and what a part holds goes inside it.  PREP
tells the point, the reasons, the examples, and the point again."
  (let ((out (org-truss-test--render org-truss-test--how-file)))
    (should (string-match-p
             (concat "^Check before every test\n\n"
                     "- Who: The driver's manager\n"
                     "- When: Before the first run of the day\n"
                     "- Where: In the office or by video call\n"
                     "- How: As follows\n\n"
                     "  1\\. Meet the driver\n"
                     "  2\\. Read the checker\n\n"
                     "What a check needs\n\n"
                     "- A checker that works\n"
                     "- Someone to check\n\n"
                     "Tests are safer checked\n\n"
                     "Alcohol slows reactions\n\n"
                     "A drunk driver crashed last year\n\n"
                     "Tests are safer checked\n")
             out)))
  (let* ((org-truss-language 'ja)
         (out (org-truss-test--render
               (replace-regexp-in-string
                ":TRUSS_ASPECTS: 5w1h" ":TRUSS_ASPECTS: 6w1h"
                (replace-regexp-in-string
                 "^\\*\\*\\* Before the first run"
                 "*** Whoever drives\n:PROPERTIES:\n:TRUSS_ROLE: whom\n:END:\n*** Before the first run"
                 org-truss-test--how-file)))))
    (should (string-match-p "^- 誰が：The driver's manager\n- 誰に：Whoever drives\n- いつ：" out))))

(ert-deftest org-truss-test-render-a-telling-on-a-member ()
  "A telling pattern on a member tells what is under it in the order of its
places, and the member itself at its own: SCQA's answer last, its title in
bold since its support comes first; what fills no place comes with the
last place.  SDS says the member, the details, and the member again."
  (let* ((text "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** We move to fortnightly reviews
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_TELLING: scqa
:END:
#+begin_public Fortnightly
We move to fortnightly reviews.
#+end_public
*** Should we keep meeting weekly
:PROPERTIES:
:TRUSS_ROLE: question
:END:
*** Half the items repeat
:PROPERTIES:
:TRUSS_ROLE: complication
:END:
*** Robin agrees
*** Reviews are weekly
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[#move]]
")
         (out (org-truss-test--render text)))
    (should (string-match-p
             (concat "^Reviews are weekly\n\nHalf the items repeat\n\nShould we keep meeting weekly\n\n"
                     "Robin agrees\n\n\\*Fortnightly\\*\nWe move to fortnightly reviews\\.\n")
             out))
    (should-not (string-match-p "^\\*+ Fortnightly" out))
    (let ((out (org-truss-test--render (replace-regexp-in-string "scqa" "sds" text))))
      (should (string-match-p
               (concat "^\\*\\* Fortnightly\nWe move to fortnightly reviews\\.\n\n"
                       "Should we keep meeting weekly\n\nHalf the items repeat\n\nRobin agrees\n\n"
                       "Reviews are weekly\n\nWe move to fortnightly reviews\\.\n")
               out)))))

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
- [[#m1]]
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

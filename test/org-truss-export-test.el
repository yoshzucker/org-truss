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
  "Parts are a bulleted list, labelled ones opening with their role in the
order of the roles, and what a part holds goes inside it.  PREP tells the
point, the reasons, the examples, and the point again."
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
                ":TRUSS_LOGIC: 5w1h" ":TRUSS_LOGIC: 6w1h"
                (replace-regexp-in-string
                 "^\\*\\*\\* Before the first run"
                 "*** Whoever drives\n:PROPERTIES:\n:TRUSS_ROLE: whom\n:END:\n*** Before the first run"
                 org-truss-test--how-file)))))
    (should (string-match-p "^- 誰が：The driver's manager\n- 誰に：Whoever drives\n- いつ：" out))))

(ert-deftest org-truss-test-render-a-purpose-on-a-member ()
  "A purpose is a how pattern like any other: on a member, its parts are
labelled with the reader's questions they answer, in the purpose's order."
  (let* ((org-truss-language 'ja)
         (out (org-truss-test--render "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** We move to fortnightly reviews
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_LOGIC: report
:END:
*** Hold them every other week
:PROPERTIES:
:TRUSS_ROLE: conclusion
:END:
*** Reviews run long
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[#move]]
")))
    (should (string-match-p
             "^We move to fortnightly reviews\n\n- 現状：Reviews run long\n- 結論：Hold them every other week\n"
             out))))

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

(provide 'org-truss-export-test)

;;; org-truss-export-test.el ends here

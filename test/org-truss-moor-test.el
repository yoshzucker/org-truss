;;; org-truss-moor-test.el --- Tests for a truss file's sources  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -L ../org-dock -L ../org-moor -L test \
;;       -l test/org-truss-moor-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss)
(require 'org-truss-core-test)
(require 'org-moor)

(ert-deftest org-truss-test-a-link-to-a-source-is-grounds ()
  "A member whose text cites a source with a moor: link has grounds; a link
under a member nested in it gives the member none."
  (org-truss-test--with
      (concat "* Subject\n:PROPERTIES:\n:TRUSS_PART: subject\n:END:\n"
              "** Premises\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: premises\n:END:\n"
              "*** Approval goes to the head first\n"
              "#+begin_quote\nThe head approves before finance.\n#+end_quote\n"
              "[[moor:6f1c::12][Approval manual p. 12]]\n"
              "*** Reviews run long\n"
              "**** Eight of twelve ran over\n[[moor:9a3e::3][Calendar l. 3]]\n")
    (let* ((model (org-truss-read))
           (approval (org-truss-test--m model "Approval goes to the head first")))
      (should (org-truss-has-grounds-p approval))
      (should (equal (org-truss-member-cited approval) "[[moor:6f1c::12][Approval manual p. 12]]"))
      (should (equal (org-truss-member-quoted approval) "The head approves before finance."))
      (should-not (org-truss-has-grounds-p (org-truss-test--m model "Reviews run long"))))))

(ert-deftest org-truss-test-sources-beside-the-file ()
  "A truss file's sources are beside it; other files' are where they were."
  (should (equal (org-truss-moor-sources "/docs/plan/truss.org") "/docs/plan/sources/"))
  (should-not (org-truss-moor-sources "/notes/journal.org"))
  (should (equal (org-moor-sources "/docs/plan/truss.org") "/docs/plan/sources/")))

(ert-deftest org-truss-test-batch-take ()
  "An agent takes a file into the truss file's sources, copied, and is
printed a link to cite it by."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file)
                                      (cons "read/minutes.txt" "We agreed.\n"))
    (let* ((truss (expand-file-name "truss.org" dir))
           (file (expand-file-name "read/minutes.txt" dir))
           (command-line-args-left (list truss file "Minutes of May"))
           (printed (with-output-to-string (org-truss-batch-take))))
      (should (string-match "\\`\\[\\[moor:\\([^]]+\\)\\]\\[Minutes of May\\]\\]\n\\'" printed))
      (let ((record (org-moor-record (match-string 1 printed) (expand-file-name "sources/" dir))))
        (should (equal (plist-get record :origin) file))
        (should (plist-get record :copy)))
      (should (file-exists-p file)))))

(ert-deftest org-truss-test-a-source-from-the-sources ()
  "A member given a source is offered the file's sources by title, and cites
the one chosen with a link; other words are written as they are."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let* ((truss (expand-file-name "truss.org" dir))
           (record (org-moor-new-source "Calendar export" "/x/cal.csv" 'file
                                        (org-moor-sources truss))))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Calendar export")))
        (should (equal (org-truss-moor-read-source nil truss)
                       (format "[[moor:%s][Calendar export]]" (plist-get record :id)))))
      (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "team agreement")))
        (should (equal (org-truss-moor-read-source nil truss) "team agreement"))))))

(ert-deftest org-truss-test-preamble-says-how-to-take ()
  "The head comment gives the check as it runs here, org-dock and all, and
how an agent takes a source when org-moor is there."
  (let ((org-truss-language 'en))
    (let ((text (org-truss--preamble)))
      (should (string-match-p "-L [^ ]+ -L [^ ]+ -l org-truss -L [^ ]+ -l org-moor -f org-truss-batch-check truss\\.org" text))
      (should-not (string-match-p "ORG-DOCK-DIR\\|ORG-MOOR-DIR\\|#TAKE" text))
      (should (string-match-p "-f org-truss-batch-take truss\\.org PATH-OR-URL" text)))
    (cl-letf (((symbol-function 'locate-library)
               (let ((locate (symbol-function 'locate-library)))
                 (lambda (name &rest args)
                   (unless (equal name "org-moor") (apply locate name args))))))
      (let ((text (org-truss--preamble)))
        (should-not (string-match-p "batch-take\\|#TAKE\\|#MOOR\\|-l org-moor" text))
        (should (string-match-p "-l org-truss -f org-truss-batch-check truss\\.org" text))))))

(ert-deftest org-truss-test-check-copy-finds-its-sources ()
  "A copy out of a truss file finds the file's sources when it is checked,
though it is kept elsewhere."
  (org-truss-test--in-directory '(("doc/truss.org" . "") ("manual.txt" . "Approve first.\n"))
    (let* ((file (expand-file-name "doc/truss.org" dir))
           (org-dock-directory (expand-file-name "dock/" dir))
           (link (org-moor-link (org-moor-take-file-to (expand-file-name "manual.txt" dir)
                                                       (org-moor-sources file) "Manual"))))
      (with-temp-file file
        (insert "#+title: T\n* Members\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n"
                "** Claim\n:PROPERTIES:\n:TRUSS_LOGIC: reasons\n:END:\n"
                "*** A fact\n:PROPERTIES:\n:TRUSS_LOGIC_ROLE: reason\n:TRUSS_GROUNDS: " link "\n:END:\n"))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (re-search-forward "^\\*\\* Claim$")
        (with-current-buffer (save-current-buffer (org-dock-heading (line-beginning-position)))
          (should (equal (org-truss-check-copy buffer-file-name (org-dock-copy-origin buffer-file-name))
                         "Nothing is left to do.\n"))
          (org-dock-abort))))))

(ert-deftest org-truss-test-export-links-to-the-origin ()
  "In the document a `moor:' link goes where its source came from: a page
on the web, at the page of a PDF; a source from a file is named as text."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let* ((truss (expand-file-name "truss.org" dir))
           (sources (org-moor-sources truss))
           (law (org-moor-new-source "Act" "https://e.x/act.pdf" 'web sources))
           (page (org-moor-new-source "Guide" "https://e.x/guide" 'web sources))
           (memo (org-moor-new-source "Memo" "/x/memo.txt" 'file sources)))
      (org-moor-record-set law :file "act.pdf")
      (should (equal (org-truss--export-moor-links
                      (format "As [[moor:%s::14][Act p. 14]] says, [[moor:%s::3]] and [[moor:%s][the memo]]; [[#m7]]."
                              (plist-get law :id) (plist-get page :id) (plist-get memo :id))
                      truss)
                     "As [[https://e.x/act.pdf#page=14][Act p. 14]] says, [[https://e.x/guide][Guide]] and the memo; [[#m7]].")))))

(provide 'org-truss-moor-test)
;;; org-truss-moor-test.el ends here

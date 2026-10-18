;;; org-truss-moor-test.el --- Tests for a truss file's sources  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -L ../org-dock -L ../org-moor -L test \
;;       -l test/org-truss-moor-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss)
(require 'org-truss-core-test)
(require 'org-moor)

(ert-deftest org-truss-test-cited-by-a-link-is-a-fact ()
  "A member whose text cites a source with a moor: link is a fact, as one
with TRUSS_SOURCE is; a link elsewhere under it does not make it one."
  (org-truss-test--with
      (concat "* Subject\n:PROPERTIES:\n:TRUSS_PART: subject\n:END:\n"
              "** Premises\n:PROPERTIES:\n:TRUSS_ROLE: premises\n:END:\n"
              "*** Approval goes to the head first\n"
              "#+begin_quote\nThe head approves before finance.\n#+end_quote\n"
              "[[moor:6f1c::12][Approval manual p. 12]]\n"
              "*** Reviews run long\n"
              "**** Eight of twelve ran over\n[[moor:9a3e::3][Calendar l. 3]]\n")
    (let ((model (org-truss-read)))
      (should (eq (org-truss-member-kind model (org-truss-test--m model "Approval goes to the head first"))
                  'fact))
      (should (equal (org-truss-member-source
                      (org-truss-test--m model "Approval goes to the head first"))
                     "[[moor:6f1c::12][Approval manual p. 12]]"))
      (should-not (org-truss-member-source (org-truss-test--m model "Reviews run long"))))))

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

(ert-deftest org-truss-test-a-fact-from-a-source ()
  "Said to be a fact, a member is offered the file's sources by title, and
cites the one chosen with a link."
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
      (should (string-match-p "-L [^ ]+ -L [^ ]+ -l org-truss -f org-truss-batch-check truss\\.org" text))
      (should-not (string-match-p "ORG-DOCK-DIR\\|ORG-MOOR-DIR\\|#TAKE" text))
      (should (string-match-p "-f org-truss-batch-take truss\\.org PATH-OR-URL" text)))
    (cl-letf (((symbol-function 'locate-library)
               (let ((locate (symbol-function 'locate-library)))
                 (lambda (name &rest args)
                   (unless (equal name "org-moor") (apply locate name args))))))
      (should-not (string-match-p "batch-take\\|#TAKE" (org-truss--preamble))))))

(provide 'org-truss-moor-test)
;;; org-truss-moor-test.el ends here

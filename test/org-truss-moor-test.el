;;; org-truss-moor-test.el --- Tests for a truss file's sources  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -L ../org-dock -L ../org-moor -L test \
;;       -l test/org-truss-moor-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss)
(require 'org-truss-core-test)
(require 'org-truss-board-test)
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
      (should (equal (org-truss-member-quoted approval) '("The head approves before finance.")))
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

(ert-deftest org-truss-test-board-takes-a-source ()
  "m on the board takes a source for the heading of the line as org-moor
takes one, into the truss file's sources, and writes the link under the
heading, after its text: grounds.  m l links one taken before."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file)
                                      (cons "read/minutes.txt" "We agreed.\n"))
    (let* ((truss (expand-file-name "truss.org" dir))
           (source (find-file-noselect truss))
           (org-truss-language 'en)
           (org-moor-move-directories nil))
      (with-temp-buffer
        (org-truss-board-mode)
        (setq org-truss--source source)
        (org-truss-board-redraw)
        (org-truss-test--goto-line-with "Reason \\[no grounds\\][ ·]+Some items are urgent")
        (cl-letf (((symbol-function 'read-file-name)
                   (lambda (&rest _) (expand-file-name "read/minutes.txt" dir)))
                  ((symbol-function 'read-string) (lambda (&rest _) "Minutes")))
          (org-truss-board-take-file))
        (let ((record (car (org-moor-sources-in (expand-file-name "sources/" dir)))))
          (should (equal (plist-get record :title) "Minutes"))
          (should (plist-get record :copy))
          (with-current-buffer source
            (should (string-search (concat "Some items cannot wait two weeks.\n"
                                           (org-moor-link record) "\n")
                                   (buffer-string))))
          (should-not (string-match-p "Reason \\[no grounds\\][ ·]+Some items are urgent" (buffer-string)))
          (should (string-match-p "⏚ source[ ·]+Minutes" (buffer-string)))
          (org-truss-test--goto-line-with "member[ ·]+Lone remark")
          (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Minutes")))
            (org-truss-board-link-source))
          (with-current-buffer source
            (should (string-search (concat "** Lone remark\n" (org-moor-link record) "\n")
                                   (buffer-string)))))))))

(ert-deftest org-truss-test-board-opens-a-source ()
  "m o on the board follows the link of a source's line, the one a
quotation quotes, or one the heading's own text has, asked for; m O opens
where a source taken by org-moor came from, and follows any other link."
  (org-truss-test--in-directory '(("truss.org" . ""))
    (let* ((truss (expand-file-name "truss.org" dir))
           (org-truss-language 'en)
           followed origins)
      (with-temp-file truss
        (insert "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_PART: message\n:END:\n"
                "** Approval goes to the head first\n"
                "#+begin_quote\nThe head approves before finance.\n"
                "[[moor:6f1c::12][Manual p. 12]]\n#+end_quote\n"
                "[[file:minutes.txt][Minutes]]\n"
                "*** Under it\n[[moor:9a3e][Calendar]]\n"))
      (with-temp-buffer
        (org-truss-board-mode)
        (setq org-truss--source (find-file-noselect truss))
        (org-truss-board-redraw)
        (cl-letf (((symbol-function 'org-link-open)
                   (lambda (link &rest _) (push (org-element-property :raw-link link) followed)))
                  ((symbol-function 'org-moor-open-origin)
                   (lambda (&rest _) (push (org-moor-link-at-point) origins)))
                  ((symbol-function 'completing-read)
                   (lambda (_ table &rest _)
                     (seq-find (lambda (name) (string-search "Minutes" name))
                               (all-completions "" table)))))
          (org-truss-test--goto-line-with "⏚ source.*Minutes")
          (org-truss-board-open-source)
          (org-truss-test--goto-line-with "⏚ quote")
          (org-truss-board-open-source)
          (org-truss-board-open-origin)
          (org-truss-test--goto-line-with "⏚ source.*Minutes")
          (org-truss-board-open-origin)
          (org-truss-test--goto-line-with "member[ ·]+Approval goes")
          (org-truss-board-open-source))
        (should (equal (reverse followed)
                       '("file:minutes.txt" "moor:6f1c::12" "file:minutes.txt" "file:minutes.txt")))
        (should (equal origins '("6f1c")))))))

(ert-deftest org-truss-test-preamble-says-how-to-take ()
  "The guide gives the check as it runs here, org-dock and all, and how an
agent takes a source when org-moor is there."
  (let ((org-truss-language 'en))
    (let ((text (org-truss-guide)))
      (should (string-match-p "-L [^ ]+ -L [^ ]+ -l org-truss -L [^ ]+ -l org-moor -f org-truss-batch-check truss\\.org" text))
      (should-not (string-match-p "ORG-DOCK-DIR\\|ORG-MOOR-DIR\\|#TAKE" text))
      (should (string-match-p "-f org-truss-batch-take truss\\.org PATH-OR-URL" text)))
    (cl-letf (((symbol-function 'locate-library)
               (let ((locate (symbol-function 'locate-library)))
                 (lambda (name &rest args)
                   (unless (equal name "org-moor") (apply locate name args))))))
      (let ((text (org-truss-guide)))
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
        (insert "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_PART: message\n:END:\n"
                "** Claim\n:PROPERTIES:\n:TRUSS_LOGIC: reasons\n:END:\n"
                "*** A fact\n:PROPERTIES:\n:TRUSS_LOGIC_ROLE: reason\n:END:\n" link "\n"))
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

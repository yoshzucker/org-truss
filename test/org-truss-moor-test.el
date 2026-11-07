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
      (concat "* Subject\n:PROPERTIES:\n:TRUSS_DIVISION: subject\n:END:\n"
              "** Premises\n"
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

(ert-deftest org-truss-test-sources-beside-a-truss-file-of-any-name ()
  "A truss file named otherwise is one by its Message division: its sources
are beside it, shared with the others there, and a place is found by the quote."
  (org-truss-test--in-directory
      (list (cons "procedure.org" org-truss-test--file)
            (cons "note.org" "#+title: N\n* A heading\n"))
    (let ((truss (expand-file-name "procedure.org" dir))
          (note (expand-file-name "note.org" dir)))
      (should (equal (org-truss-moor-sources truss) (expand-file-name "sources/" dir)))
      (should (org-truss-moor-place-by-quote-p truss))
      (should-not (org-truss-moor-sources note))
      (should-not (org-truss-moor-place-by-quote-p note))
      (with-current-buffer (find-file-noselect note)
        (goto-char (point-max))
        (insert "* M\n:PROPERTIES:\n:TRUSS_DIVISION: message\n:END:\n")
        (should (org-truss-moor-sources note))))))

(ert-deftest org-truss-test-batch-take ()
  "An agent takes a file into the truss file's sources, copied, and is
printed a link to cite it by, what to read and the replica."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file)
                                      (cons "read/minutes.txt" "We agreed.\n"))
    (let* ((truss (expand-file-name "truss.org" dir))
           (file (expand-file-name "read/minutes.txt" dir))
           (command-line-args-left (list truss file "Minutes of May"))
           (printed (with-output-to-string (org-truss-batch-take))))
      (should (string-match "\\`\\[\\[moor:\\([^]]+\\)\\]\\[Minutes of May\\]\\]\nRead: .*\nReplica: .*\n\\'" printed))
      (let ((record (org-moor-record (match-string 1 printed) (expand-file-name "sources/" dir))))
        (should (equal (plist-get record :origin-url) (org-moor-path-url file)))
        (should (plist-get record :replica)))
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
          (should (plist-get record :replica))
          (with-current-buffer source
            (should (string-search (concat "Some items cannot wait two weeks.\n"
                                           (org-moor-link record) "\n")
                                   (buffer-string))))
          (should-not (string-match-p "Reason \\[no grounds\\][ ·]+Some items are urgent" (buffer-string)))
          (org-truss--show-all 'whole)
          (should (string-match-p "Some items cannot wait two weeks\\. Minutes$" (buffer-string)))
          (org-truss--show-all 'open)
          (org-truss-test--goto-line-with "member[ ·]+Lone remark")
          (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Minutes")))
            (org-truss-board-link-source))
          (with-current-buffer source
            (should (string-search (concat "** Lone remark\n" (org-moor-link record) "\n")
                                   (buffer-string)))))))))

(ert-deftest org-truss-test-board-takes-a-source-for-an-item ()
  "m on an item takes a source as on a heading, and writes the link at the
end of the item's first line, before its tags; m l links one so."
  (org-truss-test--in-directory
      (list (cons "truss.org" "#+title: T
* Message
:PROPERTIES:
:TRUSS_DIVISION: message
:END:
** Why
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
#+attr_truss:
- Some items are urgent :draft:
  They cannot wait.
- Most items can wait
")
            (cons "read/minutes.txt" "We agreed.\n"))
    (let* ((source (find-file-noselect (expand-file-name "truss.org" dir)))
           (org-truss-language 'en)
           (org-moor-move-directories nil))
      (with-temp-buffer
        (org-truss-board-mode)
        (setq org-truss--source source)
        (org-truss-board-redraw)
        (org-truss-test--goto-line-with "Some items are urgent")
        (cl-letf (((symbol-function 'read-file-name)
                   (lambda (&rest _) (expand-file-name "read/minutes.txt" dir)))
                  ((symbol-function 'read-string) (lambda (&rest _) "Minutes")))
          (let ((this-command 'org-truss-board-take-file))
            (org-truss-board-take-file)))
        (let ((link (org-moor-link (car (org-moor-sources-in (expand-file-name "sources/" dir))))))
          (with-current-buffer source
            (should (string-search (concat "- Some items are urgent " link " :draft:\n  They cannot wait.\n")
                                   (buffer-string))))
          (org-truss-test--goto-line-with "Most items can wait")
          (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "Minutes")))
            (let ((this-command 'org-truss-board-link-source))
              (org-truss-board-link-source)))
          (with-current-buffer source
            (should (string-search (concat "- Most items can wait " link "\n") (buffer-string)))))))))

(ert-deftest org-truss-test-board-opens-a-source ()
  "m o on the board follows the link to a source at point in a member's
text, the one a quotation there quotes, or, elsewhere on the member's
lines, one its own text has, asked for; m O opens where a source taken
by org-moor came from, and follows any other link."
  (org-truss-test--in-directory '(("truss.org" . ""))
    (let* ((truss (expand-file-name "truss.org" dir))
           (org-truss-language 'en)
           followed origins)
      (with-temp-file truss
        (insert "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_DIVISION: message\n:END:\n"
                "** Approval goes to the head first\n"
                "#+begin_quote\nThe head approves before finance.\n"
                "[[moor:6f1c::12][Manual p. 12]]\n#+end_quote\n"
                "[[file:minutes.txt][Minutes]]\n"
                "*** Under it\n[[moor:9a3e][Calendar]]\n"))
      (with-temp-buffer
        (org-truss-board-mode)
        (setq org-truss--source (find-file-noselect truss))
        (org-truss-board-redraw)
        (org-truss--show-all 'whole)
        (cl-letf (((symbol-function 'org-link-open)
                   (lambda (link &rest _) (push (org-element-property :raw-link link) followed)))
                  ((symbol-function 'org-moor-open-origin)
                   (lambda (&rest _) (push (org-moor-link-at-point) origins)))
                  ((symbol-function 'completing-read)
                   (lambda (_ table &rest _)
                     (seq-find (lambda (name) (string-search "Minutes" name))
                               (all-completions "" table)))))
          (org-truss-test--goto-line-with " Minutes$")
          (search-forward "Minutes")
          (org-truss-board-open-source)
          (org-truss-test--goto-line-with "“The head")
          (search-forward "head")
          (org-truss-board-open-source)
          (org-truss-board-open-origin)
          (org-truss-test--goto-line-with " Minutes$")
          (search-forward "Minutes")
          (org-truss-board-open-origin)
          (org-truss-test--goto-line-with "member[ ·]+Approval goes")
          (org-truss-board-open-source))
        (should (equal (reverse followed)
                       '("file:minutes.txt" "moor:6f1c::12" "file:minutes.txt" "file:minutes.txt")))
        (should (equal origins '("6f1c")))))))

(ert-deftest org-truss-test-board-opens-a-source-at-its-quote ()
  "m o on a link with a quote on the line after it opens the source's
replica at the quote, the words before any left out."
  (org-truss-test--in-directory '(("truss.org" . ""))
    (let* ((truss (expand-file-name "truss.org" dir))
           (org-truss-language 'en)
           (record (org-moor-new-source "Act" "https://e.x/act" (org-moor-sources truss)))
           opened)
      (with-temp-file truss
        (insert "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_DIVISION: message\n:END:\n"
                "** The head approves first\n"
                (format "[[moor:%s][Art. 3]]\n" (plist-get record :id))
                "#+begin_quote\nThe head approves … before finance.\n#+end_quote\n"))
      (with-temp-buffer
        (org-truss-board-mode)
        (setq org-truss--source (find-file-noselect truss))
        (org-truss-board-redraw)
        (org-truss--show-all 'whole)
        (cl-letf (((symbol-function 'org-moor-open-record)
                   (lambda (r place &rest _) (setq opened (list (plist-get r :id) place)))))
          (org-truss-test--goto-line-with "member[ ·]+The head approves first")
          (org-truss-board-open-source))
        (should (equal opened (list (plist-get record :id) "The head approves")))))))

(ert-deftest org-truss-test-board-opens-an-items-source ()
  "m o on a member written as an item of a list opens a source its own
lines link to, not one of the items under it."
  (org-truss-test--in-directory
      (list (cons "truss.org" "#+title: T
* Message
:PROPERTIES:
:TRUSS_DIVISION: message
:END:
** Why
#+attr_truss:
- [[moor:6f1c][Manual]] :draft:
  It says so.
  - [[moor:9a3e][Calendar]]
- Most items can wait
"))
    (let ((org-truss-language 'en)
          followed)
      (with-temp-buffer
        (org-truss-board-mode)
        (setq org-truss--source (find-file-noselect (expand-file-name "truss.org" dir)))
        (org-truss-board-redraw)
        (org-truss--show-all 'whole)
        (org-truss-test--goto-line-with "Manual")
        (cl-letf (((symbol-function 'org-link-open)
                   (lambda (link &rest _) (push (org-element-property :raw-link link) followed))))
          (let ((this-command 'org-truss-board-open-source))
            (org-truss-board-open-source)))
        (should (equal followed '("moor:6f1c")))))))

(ert-deftest org-truss-test-preamble-says-how-to-take ()
  "The guide gives the check as it runs here, org-dock and all, and how an
agent takes a source when org-moor is there."
  (let ((org-truss-language 'en))
    (let ((text (org-truss-guide)))
      (should (string-match-p "-L [^ ]+ -L [^ ]+ -l org-truss -L [^ ]+ -l org-moor -f org-truss-batch-check truss\\.org" text))
      (should-not (string-match-p "ORG-DOCK-DIR\\|ORG-MOOR-DIR\\|#TAKE" text))
      (should (string-match-p "-f org-truss-batch-take truss\\.org REPLICA" text))
      (should (string-match-p "-f org-moor-batch-find sources/ moor:ID WORDS" text)))
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
        (insert "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_DIVISION: message\n:END:\n"
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
  "In the document a `moor:' link goes where its source is seen, at the
quote after it: a page on the web by a text fragment, a PDF at the page
it is on; a source from a file is named as text."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let* ((truss (expand-file-name "truss.org" dir))
           (sources (org-moor-sources truss))
           (law (org-moor-new-source "Act" "https://e.x/act.pdf" sources))
           (page (org-moor-new-source "Guide" "https://e.x/guide" sources))
           (memo (org-moor-new-source "Memo" "/x/memo.txt" sources)))
      (with-temp-file (expand-file-name "act.pdf" (plist-get law :dir)) (insert "%PDF"))
      (org-moor-record-set law :replica-file "act.pdf")
      (cl-letf (((symbol-function 'org-moor-pdf-pages)
                 (lambda (_) (list "one" "two" "The head approves it."))))
        (should (equal (org-truss--export-moor-links
                        (format "As [[moor:%s][Art. 3]] says,\n#+begin_quote\nThe head approves …\n#+end_quote\n[[moor:%s][Guide]]\n#+begin_quote\nPaid at month end.\n#+end_quote\nand [[moor:%s][the memo]]; [[#m7]]."
                                (plist-get law :id) (plist-get page :id) (plist-get memo :id))
                        truss)
                       (format "As [[https://e.x/act.pdf#page=3][Act Art. 3]] says,\n#+begin_quote\nThe head approves …\n#+end_quote\n[[https://e.x/guide#:~:text=%s][Guide]]\n#+begin_quote\nPaid at month end.\n#+end_quote\nand Memo the memo; [[#m7]]."
                               (url-hexify-string "Paid at month end."))))))))

(ert-deftest org-truss-test-place-by-quote ()
  "In a truss file a link to a source carries no place, the quote under it
being the place, and in the output document the first link to a source
names it: a fact included without the member naming its source above it
still says which."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let* ((truss (expand-file-name "truss.org" dir))
           (sources (org-moor-sources truss))
           (memo (org-moor-new-source "Memo" "/x/memo.txt" sources))
           (id (plist-get memo :id)))
      (should (org-moor-place-by-quote-p truss))
      (should-not (org-moor-place-by-quote-p (expand-file-name "notes.org" dir)))
      (should (string-search "[[moor:ID][WHERE]]" (org-moor-request-text (list :origin truss))))
      (should (equal (org-truss--export-moor-links
                      (format "[[moor:%s][Memo]], [[moor:%s][item 3]]; [[moor:%s][item 9]]" id id id)
                      truss)
                     "Memo, item 3; item 9"))
      (should (equal (org-truss--export-moor-links (format "[[moor:%s][item 3]]" id) truss)
                     "Memo item 3")))))

(ert-deftest org-truss-test-quote-looked-for-in-the-replica ()
  "A quote of a `moor:' source is looked for in its replica, as it is seen;
with no replica yet, it is not looked for."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let* ((truss (expand-file-name "truss.org" dir))
           (sources (org-moor-sources truss))
           (page (org-moor-new-source "Act" "https://e.x/act" sources))
           (link (format "[[moor:%s][Art. 3]]" (plist-get page :id))))
      (should-not (org-truss-quote-found "The head approves it." link truss))
      (with-temp-file (expand-file-name "act.txt" (plist-get page :dir))
        (insert "Art. 3  The head\napproves it, before finance.\n"))
      (org-moor-record-set page :replica-file "act.txt")
      (should (eq (org-truss-quote-found "The head approves it" link truss) 'found))
      (should (eq (org-truss-quote-found "The head … before finance." link truss) 'found))
      (should (eq (org-truss-quote-found "The chair approves it" link truss) 'missing)))))

(provide 'org-truss-moor-test)
;;; org-truss-moor-test.el ends here

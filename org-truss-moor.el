;;; org-truss-moor.el --- A truss file's sources, taken by org-moor  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Loaded once org-moor is, which org-truss does not need otherwise.
;;
;; A truss file keeps what was read beside it, in
;; `org-truss-sources-directory', so that the directory can be handed over
;; whole.  org-moor keeps a source as a directory there -- its replica and its
;; record -- and a member cites one with a `moor:' link in its text, which
;; gives it grounds.
;;
;; Here: the sources of a truss file are put beside it; a link to a source
;; carries no place, the quote under it, #+begin_quote, being the place,
;; and is named where in the source the quote is -- an article, a page --
;; the source named once by the apex member of the truss pointing into it;
;; a quote is looked for in the source's replica, as it is seen; `m' on the
;; board takes one for a member as org-moor takes one -- a page, a file,
;; the clipboard -- or links one taken before, for it to stand on; `m o'
;; and `m O' open a source the board's line names, its replica at the quote
;; or where it is seen, so what a member stands on is checked in it; the
;; check finds a `moor:' link to a source that is not there; the output
;; document links to where a source is seen, at the quote, not to the
;; replica, and names the source at the first link to it there; and
;; `org-truss-batch-take' takes one for an agent working in the file, which
;; cannot ask Emacs, and prints the link to cite it with.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-board)
(require 'org-moor)

(defvar org-truss-moor-missing-function)
(defvar org-truss-moor-export-function)
(defvar org-truss-moor-quote-function)
(defvar evil-local-mode)

(defun org-truss-moor-sources (file)
  "Return the sources directory of FILE when it is a truss file, else nil."
  (when (org-truss-truss-file-p file)
    (file-name-as-directory
     (expand-file-name org-truss-sources-directory (file-name-directory file)))))

(add-hook 'org-moor-sources-directory-functions #'org-truss-moor-sources)

(defun org-truss-moor-place-by-quote-p (file)
  "Non-nil when FILE is a truss file, whose links find their place by the quote.
The apex member of a truss pointing into a source names it, by its
title; the members under it quote it, a link with no place before the
quote named where in the source it is."
  (org-truss-truss-file-p file))

(add-hook 'org-moor-place-by-quote-functions #'org-truss-moor-place-by-quote-p)

;; The same from the package's autoloads, so that a truss file's sources go
;; beside it before anything of org-truss has been used: a source taken in
;; the file, or in a copy of a heading org-dock took out of it, and the
;; command an agent is handed to take one, which is written before
;; `org-truss-dock-request' loads org-truss.
;;;###autoload (autoload 'org-truss-moor-sources "org-truss")
;;;###autoload (autoload 'org-truss-moor-place-by-quote-p "org-truss")
;;;###autoload (with-eval-after-load 'org-moor (add-hook 'org-moor-sources-directory-functions #'org-truss-moor-sources) (add-hook 'org-moor-place-by-quote-functions #'org-truss-moor-place-by-quote-p))

(defun org-truss-moor--words-end (pos)
  "Return where the words of the item at POS end, before its tags."
  (save-excursion
    (goto-char pos)
    (let ((line (buffer-substring-no-properties (point) (line-end-position))))
      (+ (point) (length (string-trim-right (car (org-item-tags-split line))))))))

(defun org-truss-moor--at-item (pos thunk)
  "Call THUNK with point after the words of the item at POS and a space.
A link THUNK writes there ends the item's first line, before its tags,
as a source's place is cited; the space goes again when it writes none."
  (let ((at (copy-marker (org-truss-moor--words-end pos))))
    (goto-char at)
    (insert " ")
    (let ((after (point-marker)))
      (unwind-protect
          (let ((evil-local-mode nil))
            (funcall thunk))
        (unless (save-excursion (goto-char after) (looking-at-p "\\[\\["))
          (save-excursion (goto-char at) (when (looking-at " ") (delete-char 1))))
        (set-marker after nil)
        (set-marker at nil)))))

(defun org-truss-moor--at-heading (command)
  "Call COMMAND, an org-moor command, at the member of the board's line.
As if typed there: it reads what it reads, takes the source into the
truss file's sources, and writes the link on a line of its own after the
member's text; for an item, at the end of its first line."
  (let ((item (org-truss--want (org-truss--item) 'member)))
    (org-truss--fresh)
    (with-current-buffer org-truss--source
      (save-excursion
        (let ((pos (plist-get item :pos))
              (current-prefix-arg nil))
          (goto-char pos)
          (if (org-at-heading-p)
              (call-interactively command)
            (org-truss-moor--at-item pos (lambda () (call-interactively command)))))))
    (org-truss-board-redraw)))

(defun org-truss-board-take-url ()
  "Take a web page or a file on the web for the member at point.
Its replica is what the browser saves, as `org-moor-take-url' has it,
and the link to it written in the member's text: grounds."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-take-url))

(defun org-truss-board-take-file ()
  "Take a file for the member at point, as `org-moor-take-file' does.
The link to it is written in the member's text: grounds."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-take-file))

(defun org-truss-board-take-clipboard ()
  "Take the clipboard for the member at point, as `org-moor-take-clipboard' does.
The link to it is written in the member's text: grounds."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-take-clipboard))

(defun org-truss-board-keep-replica ()
  "Keep a replica of the sources the member at point links to that have none.
From their origins, as `org-moor-keep-replica' does: for sources an agent
took, whose replicas the browser is to save."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-keep-replica))

(defun org-truss-board-link-source ()
  "Link the member at point to a source the truss file has: grounds.
On a line of its own after the member's text."
  (interactive)
  (let ((item (org-truss--want (org-truss--item) 'member)))
    (org-truss--fresh)
    (with-current-buffer org-truss--source
      (let ((records (org-moor-sources-in (org-moor-sources))))
        (unless records
          (user-error "No sources in %s" (abbreviate-file-name (org-moor-sources))))
        (let* ((table (mapcar (lambda (r) (cons (or (plist-get r :title) (plist-get r :id)) r))
                              (sort records (lambda (a b) (string> (org-moor-record-time a)
                                                                   (org-moor-record-time b))))))
               (record (cdr (assoc (completing-read "Source: " table nil t) table)))
               (pos (plist-get item :pos)))
          (if (org-with-point-at pos (org-at-heading-p))
              (let ((at (copy-marker pos)))
                (set-marker (org-moor-insert-link-line at nil (org-moor-link record)) nil)
                (set-marker at nil))
            (save-excursion
              (org-truss-moor--at-item pos (lambda () (insert (org-moor-link record)))))))))
    (org-truss-board-redraw)))

(defun org-truss-moor--item-text-end (pos)
  "Return where the text of the item at POS ends, before the items under it."
  (org-with-wide-buffer
   (goto-char pos)
   (let* ((struct (org-list-struct))
          (under (car (org-list-get-children pos struct (org-list-parents-alist struct)))))
     (or under (org-list-get-item-end pos struct)))))

(defun org-truss-moor--open (origin how)
  "Open a source of the board's line, as following its link does.
On a link to a source drawn in a member's text, that one; on a quotation
there, a link in it or else the first the text cites; elsewhere on a
member's lines, one its own words or text link to, asked for when several --
not those of the members under it, which the board shows under them.  A
member written as an item of a list, by the item's own lines.
ORIGIN opens where a source taken by org-moor came from rather than its
replica; any other link is followed either way.  HOW is the prefix, as for
following a link."
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (pos (plist-get item :pos))
         (here (get-text-property (point) 'org-truss-link)))
    (org-truss--fresh)
    (let ((in-item (org-truss--item-holder pos)))
      (with-current-buffer org-truss--source
        (let* ((item-end (and in-item (org-truss-moor--item-text-end pos)))
               (links (or (and here (string-match-p (concat "\\`" org-truss--source-link-re "\\'") here)
                               (list here))
                          (seq-uniq (org-truss--source-links-in
                                     (if item-end
                                         (org-with-wide-buffer (buffer-substring-no-properties pos item-end))
                                       (concat (org-with-point-at pos
                                                 (if (org-at-heading-p) (org-truss--heading-words) ""))
                                               "\n" (plist-get (org-truss--text-at pos) :all)))))
                          (user-error "No source here")))
               (link (if (cdr links)
                         (org-truss--read-choice
                          "Source: " (mapcar (lambda (l) (cons (concat (org-truss--link-text l) "  " l) l))
                                             links))
                       (car links)))
               (end (or item-end (cdr (org-truss--text-bounds pos)))))
          (save-excursion
            ;; Point on the link, so it is followed from where it is written:
            ;; a file beside the truss file, the member a replica is read for.
            (goto-char pos)
            (unless (search-forward link end t)
              (user-error "The link is no longer in the member's text: %s" link))
            (goto-char (match-beginning 0))
            (let ((quote (and (string-prefix-p "[[moor:" link)
                              (org-truss-moor--quote-after (match-end 0) end))))
              (cond ((and origin (string-prefix-p "[[moor:" link))
                     (org-moor-open-origin how))
                    (quote
                     (org-moor-open-record
                      (or (org-moor-find-record (org-moor-link-at-point))
                          (user-error "No source %s" link))
                      (org-moor-text-place (car (split-string quote "…\\|\\.\\.\\." t "[[:space:]]+")))
                      (org-moor--heading-marker) how))
                    (t (org-open-at-point how))))))))))

(defun org-truss-moor--quote-after (from end)
  "Return the words of the quote right after the link ending at FROM, or nil.
The quote, #+begin_quote, on the line after the link's, before END: the
place a link in a truss file finds."
  (save-excursion
    (goto-char from)
    (forward-line 1)
    (when (and (< (point) end)
               (looking-at "[ \t]*#\\+begin_quote\\b.*\n"))
      (let ((start (match-end 0)))
        (when (re-search-forward "^[ \t]*#\\+end_quote" end t)
          (string-trim (buffer-substring-no-properties start (match-beginning 0))))))))

(defun org-truss-board-open-source (&optional how)
  "Open the replica of a source of the board's line, or follow its link.
At the quote on the line after the link, when there is one.  On a link to
a source in a member's text, that one; on a quotation there, the one it
quotes; elsewhere, one the member's text links to.  HOW, the prefix, as
for following a link: \\[universal-argument] in Emacs, two in the program
the system opens it with."
  (interactive "P")
  (org-truss-moor--open nil how))

(defun org-truss-board-open-origin (&optional how)
  "Open where a source of the board's line came from.
As `org-truss-board-open-source' finds it; a link to anything but a
source taken by org-moor is followed as it is."
  (interactive "P")
  (org-truss-moor--open t how))

(define-key org-truss-board-moor-map (kbd "o") #'org-truss-board-open-source)
(define-key org-truss-board-moor-map (kbd "O") #'org-truss-board-open-origin)
(define-key org-truss-board-moor-map (kbd "w") #'org-truss-board-take-url)
(define-key org-truss-board-moor-map (kbd "f") #'org-truss-board-take-file)
(define-key org-truss-board-moor-map (kbd "c") #'org-truss-board-take-clipboard)
(define-key org-truss-board-moor-map (kbd "k") #'org-truss-board-keep-replica)
(define-key org-truss-board-moor-map (kbd "l") #'org-truss-board-link-source)

(defun org-truss-moor-missing-p (id file)
  "Non-nil when the sources of FILE hold no source ID.
FILE is the file the link to it is in; with none, the current buffer's."
  (not (org-moor-record id (org-moor-sources file))))

(setq org-truss-moor-missing-function #'org-truss-moor-missing-p)

(defun org-truss-moor-quote-found (path words file)
  "Return whether WORDS are in the replica of the `moor:' link PATH of FILE.
`found', `not-found', or nil when it has no replica yet; as
`org-moor-words-in-replica' looks: the replica as it is seen, a page, a
PDF, a document."
  (let ((record (ignore-errors (org-moor-record (car (org-moor-link-parse path))
                                                (org-moor-sources file)))))
    (and record
         (pcase (org-moor-words-in-replica record words)
           ('found 'found)
           ('not-found 'not-found)))))

(setq org-truss-moor-quote-function #'org-truss-moor-quote-found)

(defun org-truss-moor-export-link (path words file &optional first quote)
  "Return the `moor:' link to PATH, named WORDS, as the reader of FILE follows it.
The reader has no replica of the source, so the link goes to its origin: a
page on the web, at QUOTE, the quote after the link, when there is one --
by a text fragment, #:~:text=, or the page of a PDF it is on.  A source
that came from no such page -- a file, a mail -- is named by WORDS, or its
title, as text, since nothing there can be opened by the reader.  FIRST,
the first link to the source in the output document, has the title before
WORDS naming where in it: a fact included without the member naming its
source above it is not left without it."
  (pcase-let* ((`(,id . ,place) (org-moor-link-parse path))
               (record (org-moor-record id (org-moor-sources file)))
               (origin (plist-get record :origin-url))
               (title (plist-get record :title))
               (name (cond ((not words) (or title id))
                           ((and first title (not (equal words title)))
                            (concat title " " words))
                           (t words)))
               (at (let ((words (or quote place)))
                     (and words (car (split-string words "…\\|\\.\\.\\." t "[[:space:]]+"))))))
    (if (not (and origin (string-match-p "\\`https?://" origin)))
        name
      (org-link-make-string
       (cond ((or (not at) (string-search "#" origin)) origin)
             ((equal (org-moor-extension (or (plist-get record :replica-file) origin)) "pdf")
              (let ((page (and (plist-get record :replica)
                               (ignore-errors (org-moor-pdf-page-of (plist-get record :replica) at)))))
                (if page (format "%s#page=%d" origin page) origin)))
             (t (concat origin "#:~:text=" (url-hexify-string (org-moor-text-place at)))))
       name))))

(setq org-truss-moor-export-function #'org-truss-moor-export-link)

(defun org-truss-batch-take ()
  "Take a file or a web page into a truss file's sources, and print a link to it.
For an agent working in the file, which cannot ask Emacs:

  emacs --batch -L DIR ... -l org-truss -l org-moor \\
        -f org-truss-batch-take truss.org REPLICA [TITLE] [OPTION...]

As `org-moor-batch-take' takes it into the truss file's sources, with its
options: a file is the replica, a URL awaits the user's browser, and
--origin-url, --machine-readable and --machine-readable-url say where it
is seen and what a machine reads better.  The link printed names the
source by its title; written in an apex member's words, it names the
source, and under it, with a quote, it cites it."
  (let ((truss (expand-file-name (or (pop command-line-args-left)
                                     (error "org-truss: no truss file")))))
    (setq command-line-args-left (cons (org-moor-sources truss) command-line-args-left))
    (org-moor-batch-take)))

(provide 'org-truss-moor)
;;; org-truss-moor.el ends here

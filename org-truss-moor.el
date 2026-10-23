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
;; whole.  org-moor keeps a source as a directory there -- its copy and its
;; record -- and a member cites one with a `moor:' link in its text, which
;; gives it grounds.
;;
;; Here: the sources of a truss file are put beside it; `m' on the board
;; takes one for a heading as org-moor takes one -- a page, a file, the
;; clipboard -- or links one taken before, for it to stand on; `m o' and
;; `m O' open a source the board's line names, its copy or where it came
;; from, so what a heading stands on is read beside it; the check finds a
;; `moor:' link to a source that is not there; the document links to
;; where a source came from, not to the copy; and
;; `org-truss-batch-take' takes one for an agent working in the file, which
;; cannot ask Emacs, and prints the link to cite it with.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-board)
(require 'org-moor)

(defvar org-truss-moor-missing-function)
(defvar org-truss-moor-export-function)

(defun org-truss-moor-sources (file)
  "Return the sources directory of FILE when it is a truss file, else nil."
  (when (equal (file-name-nondirectory file) org-truss-file-name)
    (file-name-as-directory
     (expand-file-name org-truss-sources-directory (file-name-directory file)))))

(add-hook 'org-moor-sources-directory-functions #'org-truss-moor-sources)

(defun org-truss-moor--at-heading (command)
  "Call COMMAND, an org-moor command, at the heading of the board's line.
As if typed there: it reads what it reads, takes the source into the
truss file's sources, and writes the link on a line of its own after the
heading's text, outside its public block."
  (let ((item (org-truss--want (org-truss--item) 'member 'section)))
    (org-truss--fresh)
    (with-current-buffer org-truss--source
      (save-excursion
        (goto-char (plist-get item :pos))
        (let ((current-prefix-arg nil))
          (call-interactively command))))
    (org-truss-board-redraw)))

(defun org-truss-board-take-url ()
  "Take a web page or a file on the web for the heading at point.
Its copy is fetched in the background, as `org-moor-take-url' fetches it,
and the link to it written under the heading: grounds."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-take-url))

(defun org-truss-board-take-file ()
  "Take a file for the heading at point, as `org-moor-take-file' does.
The link to it is written under the heading: grounds."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-take-file))

(defun org-truss-board-take-clipboard ()
  "Take the clipboard for the heading at point, as `org-moor-take-clipboard' does.
The link to it is written under the heading: grounds."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-take-clipboard))

(defun org-truss-board-keep-copy ()
  "Keep a copy of the sources the heading at point links to that have none.
From their origins, as `org-moor-keep-copy' does: for sources an agent
took, which could not fetch them as you, signed in."
  (interactive)
  (org-truss-moor--at-heading #'org-moor-keep-copy))

(defun org-truss-board-link-source ()
  "Link the heading at point to a source the truss file has: grounds.
On a line of its own after the heading's text, outside its public block."
  (interactive)
  (let ((item (org-truss--want (org-truss--item) 'member 'section)))
    (org-truss--fresh)
    (with-current-buffer org-truss--source
      (let ((records (org-moor-sources-in (org-moor-sources))))
        (unless records
          (user-error "No sources in %s" (abbreviate-file-name (org-moor-sources))))
        (let* ((table (mapcar (lambda (r) (cons (or (plist-get r :title) (plist-get r :id)) r))
                              (sort records (lambda (a b) (string> (or (plist-get a :taken) "")
                                                                   (or (plist-get b :taken) ""))))))
               (record (cdr (assoc (completing-read "Source: " table nil t) table)))
               (at (copy-marker (plist-get item :pos))))
          (set-marker (org-moor-insert-link-line at nil (org-moor-link record)) nil)
          (set-marker at nil))))
    (org-truss-board-redraw)))

(defun org-truss-moor--open (origin how)
  "Open a source of the board's line, as following its link does.
A source's line opens its own; a quotation's, a link in it or else the
first the text cites; a heading's, one its own text links to, asked for
when several -- not those of the headings under it, which the board shows
under them.  ORIGIN opens where a source taken by org-moor came from
rather than its copy; any other link is followed either way.  HOW is the
prefix, as for following a link."
  (let* ((item (org-truss--want (org-truss--item) 'member 'section))
         (pos (plist-get item :pos)))
    (org-truss--fresh)
    (with-current-buffer org-truss--source
      (let* ((links (or (plist-get item :links)
                        (seq-uniq (org-truss--source-links-in
                                   (org-truss--text (org-truss--own pos))))
                        (user-error "No source here")))
             (link (if (cdr links)
                       (org-truss--read-choice
                        "Source: " (mapcar (lambda (l) (cons (concat (org-truss--link-text l) "  " l) l))
                                           links))
                     (car links)))
             (end (cdr (org-truss--own-bounds pos))))
        (save-excursion
          ;; Point on the link, so it is followed from where it is written:
          ;; a file beside the truss file, the heading a copy is read for.
          (goto-char pos)
          (unless (search-forward link end t)
            (user-error "The link is no longer under the heading: %s" link))
          (goto-char (match-beginning 0))
          (if (and origin (string-prefix-p "[[moor:" link))
              (org-moor-open-origin how)
            (org-open-at-point how)))))))

(defun org-truss-board-open-source (&optional how)
  "Open the copy of a source of the board's line, or follow its link.
On a source's line, its own; on a quotation's, the one it quotes; on a
heading's, one its text links to.  HOW, the prefix, as for following a
link: \\[universal-argument] in Emacs, two in the program the system opens it with."
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
(define-key org-truss-board-moor-map (kbd "k") #'org-truss-board-keep-copy)
(define-key org-truss-board-moor-map (kbd "l") #'org-truss-board-link-source)

(defun org-truss-moor-missing-p (id file)
  "Non-nil when the sources of FILE hold no source ID.
FILE is the file the link to it is in; with none, the current buffer's."
  (not (org-moor-record id (org-moor-sources file))))

(setq org-truss-moor-missing-function #'org-truss-moor-missing-p)

(defun org-truss-moor-export-link (path words file)
  "Return the `moor:' link to PATH, named WORDS, as the reader of FILE follows it.
The reader has no copy of the source, so the link goes to its origin: a
page on the web, at the page of a PDF the link names.  A source that came
from no such page -- a file, a mail -- is named by WORDS, or its title, as
text, since nothing there can be opened by the reader."
  (pcase-let* ((`(,id . ,place) (org-moor-link-parse path))
               (record (org-moor-record id (org-moor-sources file)))
               (origin (plist-get record :origin))
               (name (or words (plist-get record :title) id)))
    (if (not (and origin (string-match-p "\\`https?://" origin)))
        name
      (org-link-make-string
       (if (and (integerp place)
                (not (string-search "#" origin))
                (equal (org-moor-extension (or (plist-get record :file) origin)) "pdf"))
           (format "%s#page=%d" origin place)
         origin)
       name))))

(setq org-truss-moor-export-function #'org-truss-moor-export-link)

(defun org-truss-batch-take ()
  "Take a file or a web page into a truss file's sources, and print a link to it.
For an agent working in the file, which cannot ask Emacs:

  emacs --batch -L DIR ... -l org-truss -l org-moor \\
        -f org-truss-batch-take truss.org FILE-OR-URL [TITLE]

A file is copied, never moved, and titled by its name unless TITLE is
given.  The link printed names the source by its title; written in a
member's text, it cites the source, and with a place,
::12 after the id, a page of a PDF or a line of anything else."
  (let* ((truss (expand-file-name (or (pop command-line-args-left)
                                      (error "org-truss: no truss file"))))
         (what (or (pop command-line-args-left)
                   (error "org-truss: no file or URL to take")))
         (title (pop command-line-args-left))
         (sources (org-moor-sources truss))
         (record (if (string-match-p "\\`https?://" what)
                     (org-moor-take-url-to what sources title t)
                   (unless (file-regular-p what)
                     (error "org-truss: not a file: %s" what))
                   (org-moor-take-file-to what sources title))))
    (princ (concat (org-moor-link record) "\n"))))

(provide 'org-truss-moor)
;;; org-truss-moor.el ends here

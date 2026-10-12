;;; org-truss.el --- Build arguments from members and arrange them into a document  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; Author: yoshzucker
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6"))
;; Keywords: outlines, wp
;; URL: https://github.com/yoshzucker/org-truss

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A document that argues for something -- a proposal, an explanation -- is
;; built here the way a truss is: members first, each written once; then
;; arguments, members joined so that a claim stands on what supports it; then
;; the structure, sections that answer the reader's questions and show those
;; arguments in order.  What the reader sees is the headings, or the public
;; blocks written under them; everything else stays in the file, and the
;; document is generated from it.
;;
;; `org-truss-init'            start a truss.org
;; `org-truss-board'           draw the structure, change it, see what is undone
;; `org-truss-check'           list what is undone, line by line
;; `org-truss-export'          write the document
;; `org-truss-refresh-guides'  put the current guidance back into a truss.org
;; `org-truss-convert-references'
;;                             point by CUSTOM_ID where a heading is named
;;
;; See README.org.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-export)
(require 'org-truss-board)

;; Every command loads this file first, whichever library defines it, so that
;; a configuration waiting on `org-truss' is in place before the first one runs.
;;;###autoload (autoload 'org-truss-board "org-truss" "Draw the board for the nearest truss file." t)
;;;###autoload (autoload 'org-truss-export "org-truss" "Write the document of the nearest truss file." t)

;;;###autoload
(defun org-truss-init (directory)
  "Open the truss file in DIRECTORY, writing a new one when there is none."
  (interactive (list (read-directory-name "Directory: " (org-truss--default-directory))))
  (let ((file (expand-file-name org-truss-file-name directory)))
    (if (file-exists-p file)
        (find-file file)
      (let ((title (read-string "Title: ")))
        (find-file file)
        (insert (org-truss-skeleton title))
        (goto-char (point-min))))))

;;;###autoload
(defun org-truss-refresh-guides ()
  "Put the current guidance back into the nearest truss file.
The comment block at its head and the :GUIDE: drawers are written anew, or
added where they were deleted; nothing you wrote is touched.  The buffer is
left unsaved, to be looked over."
  (interactive)
  (let ((file (or (org-truss-locate)
                  (user-error "No %s here or above" org-truss-file-name))))
    (with-current-buffer (find-file-noselect file)
      (org-truss-refresh-guides-in-buffer)
      (message "org-truss: guidance in %s is current; not saved yet"
               (abbreviate-file-name file)))))

;;;###autoload
(defun org-truss-check ()
  "List what the nearest truss file leaves undone, a line for each thing.
What the board shows under each part, as text: under each check, what it
finds and where, by line.  RET on a line visits it."
  (interactive)
  (let* ((file (or (org-truss-locate)
                   (user-error "No %s here or above" org-truss-file-name)))
         (report (with-current-buffer (find-file-noselect file)
                   (org-truss-check-report (org-truss-read)))))
    (with-current-buffer (get-buffer-create "*org-truss-check*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq default-directory (file-name-directory file))
        (insert report))
      (compilation-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

;;;###autoload
(defun org-truss-convert-references ()
  "Make the nearest truss file point to its members by CUSTOM_ID.
A link [[*heading]] in the structure, and a heading named in
TRUSS_GROUNDS, become [[#id]], and the member named is given an id when it
has none; a link keeps its words.  For a file written before members were
pointed to by id, or a link written by heading.  The buffer is left
unsaved, to be looked over."
  (interactive)
  (let ((file (or (org-truss-locate)
                  (user-error "No %s here or above" org-truss-file-name))))
    (with-current-buffer (find-file-noselect file)
      (message "org-truss: %d references in %s point by id now; not saved yet"
               (org-truss-convert-references-in-buffer)
               (abbreviate-file-name file)))))

(defun org-truss-batch-check ()
  "Print what the truss file named on the command line leaves undone.

  emacs --batch -L DIR -l org-truss -f org-truss-batch-check truss.org

Each line reads FILE:LINE: and what is there, under the check that
finds it."
  (let ((file (pop command-line-args-left)))
    (with-current-buffer (find-file-noselect file)
      (princ (org-truss-check-report (org-truss-read) file)))))

(defun org-truss-batch-board ()
  "Print the board of the truss file named on the command line.

  emacs --batch -L DIR -l org-truss -f org-truss-batch-board truss.org"
  (let ((file (pop command-line-args-left)))
    (with-current-buffer (find-file-noselect file)
      (princ (substring-no-properties (org-truss-board-text (org-truss-read)))))))

(defun org-truss-batch-export ()
  "Write the document of the truss file named on the command line.

  emacs --batch -L DIR -l org-truss -f org-truss-batch-export truss.org"
  (let ((file (pop command-line-args-left)))
    (dolist (written (org-truss-export-buffer (find-file-noselect file)))
      (princ (format "%s\n" written)))))

(provide 'org-truss)

;;; org-truss.el ends here

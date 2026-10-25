;;; org-truss.el --- Build trusses of members and arrange them into a document  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; Author: yoshzucker
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6") (org-dock "0.1"))
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
;; built here the way a truss is: members, each one heading or one item of
;; a list; trusses, a member with a pattern and the members right under it,
;; so that a claim stands on what supports it; and Structure, the outline
;; of the output document, which includes those trusses where they are
;; told.  What the reader sees is the members' words and text; a comment
;; stays in the file, and the output document is written from it.
;;
;; `org-truss-init'            set up a directory: a truss.org, what goes beside it
;; `org-truss-board'           draw the trusses, change them, see what is undone
;; `org-truss-check'           list what is undone, line by line
;; `org-truss-export'          write the output document
;; `org-truss-refresh-guides'  put the current guide back into a truss.org
;;
;; See README.org.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-edit)
(require 'org-truss-guide)
(require 'org-truss-export)
(require 'org-truss-board)

;; Sources taken by org-moor, when it is there: a truss file's go beside
;; it, and a member can take one, or cite one, from the board.
(with-eval-after-load 'org-moor
  (require 'org-truss-moor))

;; Every command loads this file first, whichever library defines it, so that
;; a configuration waiting on `org-truss' is in place before the first one runs.
;;;###autoload (autoload 'org-truss-board "org-truss" "Draw the board for the nearest truss file." t)
;;;###autoload (autoload 'org-truss-export "org-truss" "Write the output document of the nearest truss file." t)
;;;###autoload (autoload 'org-truss-apply-pattern "org-truss" "Give the heading at point a pattern, in any Org file." t)

(defcustom org-truss-project-file nil
  "Empty file `org-truss-init' writes beside the truss file, or nil.
A file whose name a project tool takes as the mark of a project's root --
\".project\", say, with `project-vc-extra-root-markers' naming it -- so
that the directory is a project of its own even outside a repository, and
what starts at a project's root, a coding agent among them, starts beside
the truss file and its sources.  Inside a repository it makes the
directory a project apart from the rest."
  :type '(choice (const :tag "None" nil) string)
  :group 'org-truss)

(defun org-truss-set-up-directory (directory)
  "Put beside the truss file in DIRECTORY what is missing of what goes there.
The directories `org-truss-sources-directory' and
`org-truss-notes-directory', and `org-truss-project-file'.  What is
there is left as it is.  Return the names of what was made."
  (let (made)
    (dolist (dir (list org-truss-sources-directory org-truss-notes-directory))
      (let ((path (expand-file-name dir directory)))
        (unless (file-directory-p path)
          (make-directory path t)
          (push (file-name-as-directory dir) made))))
    (when org-truss-project-file
      (let ((path (expand-file-name org-truss-project-file directory)))
        (unless (file-exists-p path)
          (with-temp-file path)
          (push org-truss-project-file made))))
    (nreverse made)))

;;;###autoload
(defun org-truss-init (directory)
  "Set up DIRECTORY to make a document in, and open its truss file.
A new truss file, written to disk, when there is none.  Beside it, what
is missing of the directories its guide names and of
`org-truss-project-file'; see `org-truss-set-up-directory'.  A truss
file written before its attachments were kept beside it is given the
line that keeps them there, left unsaved to be looked over."
  (interactive (list (read-directory-name "Directory: " (org-truss--default-directory))))
  (let* ((file (expand-file-name org-truss-file-name directory))
         (new (not (file-exists-p file)))
         (title (and new (read-string "Title: "))))
    (make-directory directory t)
    ;; Written before it is visited, so that the file is there from the
    ;; start and its first line's variables are taken as on any visit.
    (when new
      (let ((coding-system-for-write 'utf-8-unix))
        (with-temp-file file (insert (org-truss-skeleton title)))))
    (find-file file)
    (unless new
      (org-truss-put-file-variables))
    (let ((made (org-truss-set-up-directory directory)))
      (when made
        (message "org-truss: made %s in %s" (string-join made ", ")
                 (abbreviate-file-name (file-name-as-directory directory)))))))

;;;###autoload
(defun org-truss-refresh-guides ()
  "Put the current guide back into the nearest truss file.
The comment block at its head and the :GUIDE: drawers are written anew, or
added where they were deleted; nothing you wrote is touched.  The buffer is
left unsaved, to be looked over."
  (interactive)
  (let ((file (or (org-truss-locate)
                  (user-error "No %s here or above" org-truss-file-name))))
    (with-current-buffer (find-file-noselect file)
      (org-truss-refresh-guides-in-buffer)
      (message "org-truss: the guide in %s is current; not saved yet"
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

(defun org-truss-batch-check ()
  "Print what the Org file named on the command line leaves undone.

  emacs --batch -L DIR -l org-truss -f org-truss-batch-check truss.org

Each line reads FILE:LINE: and what is there, under the check that
finds it.  A truss file is read whole; any other Org file as the board
of one heading reads it, each heading with a pattern and none above it
with one.  A copy org-dock took out is read written back where it came
from; see `org-truss-check-copy'."
  (let* ((file (pop command-line-args-left))
         (origin (org-dock-copy-origin (expand-file-name file))))
    (princ
     (if origin
         (org-truss-check-copy file origin)
       (with-current-buffer (find-file-noselect file)
         (org-truss--check-in file (org-truss--check-groups-here)))))))

(defun org-truss--check-in (file groups)
  "Return GROUPS, of `org-truss-check-groups', as a report on FILE's lines."
  (org-truss-check-text
   (mapcar (lambda (group)
             (cons (car group)
                   (mapcar (lambda (item) (list file (car item) (cdr item))) (cdr group))))
           groups)))

(defun org-truss--pattern-tops ()
  "Return markers at the headings with a pattern and none above them with one."
  (org-with-wide-buffer
   (delq nil (org-map-entries
              (lambda ()
                (and (org-truss--patterned-p)
                     (save-excursion
                       (not (cl-loop while (org-up-heading-safe)
                                     thereis (org-truss--patterned-p))))
                     (point-marker)))))))

(defun org-truss--check-groups-here ()
  "Return what this buffer leaves undone, as `org-truss-check-groups' does.
A truss file is read whole.  Any other Org file is read as the board of
one heading reads it, for each heading with a pattern and none above it
with one; what they find is put together."
  (if (org-truss-file-p)
      (org-truss-check-groups (org-truss-read))
    (let (groups)
      (dolist (top (org-truss--pattern-tops))
        (setq org-truss--alone top)
        (dolist (group (org-truss-check-groups (org-truss-read)))
          (let ((cell (assoc (car group) groups)))
            (if cell
                (setcdr cell (seq-uniq (append (cdr cell) (cdr group))))
              (push (cons (car group) (cdr group)) groups))))
        (set-marker top nil))
      (setq org-truss--alone nil)
      (nreverse groups))))

(defun org-truss--check-as (file text)
  "Return what FILE would leave undone, holding TEXT, by its groups.
Read in a buffer of its own, as FILE is read by its name and directory,
with the file's safe variables; FILE itself is not visited."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert text))
    (let ((buffer-file-name file)
          (default-directory (file-name-directory file))
          (enable-local-variables :safe))
      (delay-mode-hooks (org-mode))
      (hack-local-variables)
      (prog1 (org-truss--check-groups-here)
        (set-buffer-modified-p nil)))))

(defun org-truss--line-count (text)
  "Return the number of lines TEXT takes."
  (+ (cl-count ?\n text)
     (if (or (string-empty-p text) (string-suffix-p "\n" text)) 0 1)))

(defun org-truss-check-copy (copy origin)
  "Return what the copy in the file COPY leaves undone, as a report.
ORIGIN is what `org-dock-copy-origin' says of it.  The copy is read
written back over what was taken out of the file it came from, so that
links, grounds and sources are found as they will be: what is in the
copy is given by the copy's lines, and what is outside it only when the
copy brings it about, by the file's lines."
  (let* ((file (plist-get origin :file))
         (old (plist-get origin :original))
         (read (lambda (f) (with-temp-buffer
                             (let ((coding-system-for-read 'utf-8))
                               (insert-file-contents f))
                             (buffer-string))))
         (new (funcall read copy))
         (new (if (and (string-suffix-p "\n" old) (not (string-suffix-p "\n" new)))
                  (concat new "\n")
                new))
         (before (funcall read file))
         (at (if (string= old before)
                 0
               (let ((i (string-search old before)))
                 (and i (not (string-search old before (1+ i))) i)))))
    (unless at
      (error "org-truss: %s has changed where the copy was taken out" file))
    (let* ((first (1+ (cl-count ?\n (substring before 0 at))))
           (old-n (org-truss--line-count old))
           (new-n (org-truss--line-count new))
           (after (concat (substring before 0 at) new (substring before (+ at (length old)))))
           (base (org-truss--check-as file before)))
      (org-truss-check-text
       (mapcar
        (lambda (group)
          (let ((was (cdr (assoc (car group) base))))
            (cons (car group)
                  (delq nil
                        (mapcar
                         (lambda (item)
                           (let ((line (car item)))
                             (cond ((and (>= line first) (< line (+ first new-n)))
                                    (list copy (1+ (- line first)) (cdr item)))
                                   ((let ((line (if (< line first) line (- line (- new-n old-n)))))
                                      (and (not (member (cons line (cdr item)) was))
                                           (list file line (cdr item))))))))
                         (cdr group))))))
        (org-truss--check-as file after))))))

(defun org-truss-batch-guide ()
  "Print the guide of a truss file, and what each part and role is for.

  emacs --batch -L DIR -l org-truss -f org-truss-batch-guide

In `org-truss-language': the guide, as the drawer at a truss file's head
holds it, then what the board's ? says of each part and of each role of
Brief's and Subject's breakdowns."
  (princ (org-truss-guide))
  (princ (concat "\n" (org-truss--pick "What each part and role is for"
                                       "部と役が何を書く所か")
                 "\n"))
  (pcase-dolist (`(,key . ,_) org-truss--part-guides)
    (let* ((part (if (consp key) (car key) key))
           (role (and (consp key) (cadr key))))
      (princ (format "  %s%s: %s\n"
                     (capitalize (symbol-name part))
                     (if role (concat " › " (org-truss-role-name role)) "")
                     (replace-regexp-in-string "[ \t]*\n[ \t]*" (org-truss--pick " " "")
                                               (org-truss-part-guide part role)))))))

(defun org-truss-batch-board ()
  "Print the board of the truss file named on the command line.

  emacs --batch -L DIR -l org-truss -f org-truss-batch-board truss.org"
  (let ((file (pop command-line-args-left)))
    (with-current-buffer (find-file-noselect file)
      (princ (substring-no-properties (org-truss-board-text (org-truss-read)))))))

(defun org-truss-batch-export ()
  "Write the output document of the truss file named on the command line.

  emacs --batch -L DIR -l org-truss -f org-truss-batch-export truss.org"
  (let ((file (pop command-line-args-left)))
    (dolist (written (org-truss-export-buffer (find-file-noselect file)))
      (princ (format "%s\n" written)))))

(provide 'org-truss)

;;; org-truss.el ends here

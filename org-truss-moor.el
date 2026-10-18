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
;; record -- and a fact cites one with a `moor:' link, in its text or in
;; TRUSS_SOURCE; either makes it a fact.
;;
;; Here: the sources of a truss file are put beside it; `t' on the board
;; offers them, or takes one there and then, when a fact is said to be one;
;; and `org-truss-batch-take' takes one for an agent working in the file,
;; which cannot ask Emacs, and prints the link to cite it with.

;;; Code:

(require 'org-truss-core)
(require 'org-moor)

(defvar org-truss-read-source-function)

(defun org-truss-moor-sources (file)
  "Return the sources directory of FILE when it is a truss file, else nil."
  (when (equal (file-name-nondirectory file) org-truss-file-name)
    (file-name-as-directory
     (expand-file-name org-truss-sources-directory (file-name-directory file)))))

(add-hook 'org-moor-sources-directory-functions #'org-truss-moor-sources)

(defconst org-truss-moor--take-file "Take a file..."
  "What `org-truss-moor-read-source' offers to take a file by.")

(defconst org-truss-moor--take-url "Take a web page..."
  "What `org-truss-moor-read-source' offers to take a web page by.")

(defun org-truss-moor-read-source (default file)
  "Read where a fact comes from: a source of FILE's, one taken now, or words.
A source of the truss file FILE, by its title, is cited by a link to it;
a file or a web page can be taken into its sources there and then; any
other answer is written as it is.  DEFAULT is what the fact says now."
  (let* ((sources (org-moor-sources file))
         (records (sort (org-moor-sources-in sources)
                        (lambda (a b) (string< (or (plist-get a :title) "")
                                               (or (plist-get b :title) "")))))
         (table (append (mapcar (lambda (r) (cons (or (plist-get r :title) (plist-get r :id)) r))
                                records)
                        (list (cons org-truss-moor--take-file 'file)
                              (cons org-truss-moor--take-url 'url))))
         (answer (string-trim (completing-read "Source (a source, or words): "
                                               (mapcar #'car table) nil nil nil nil
                                               default))))
    (pcase (cdr (assoc answer table))
      ('file
       (let ((path (read-file-name "Take file: " nil nil t)))
         (org-moor-link
          (org-moor-take-file-to path sources
                                 (read-string "Title: " (file-name-sans-extension
                                                         (file-name-nondirectory path)))))))
      ('url
       (let ((url (read-string "URL: ")))
         (org-moor-link
          (org-moor-take-url-to url sources
                                (read-string "Title: " (let ((name (org-moor-url-file-name url)))
                                                         (and name (file-name-sans-extension name))))))))
      ((and (pred consp) record) (org-moor-link record))
      (_ answer))))

(setq org-truss-read-source-function #'org-truss-moor-read-source)

(defun org-truss-batch-take ()
  "Take a file or a web page into a truss file's sources, and print a link to it.
For an agent working in the file, which cannot ask Emacs:

  emacs --batch -L DIR ... -l org-truss -l org-moor \\
        -f org-truss-batch-take truss.org FILE-OR-URL [TITLE]

A file is copied, never moved, and titled by its name unless TITLE is
given.  The link printed names the source by its title; written where a
fact is, it cites the source, and with a place, ::12 after the id, a page
of a PDF or a line of anything else."
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

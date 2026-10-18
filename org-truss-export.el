;;; org-truss-export.el --- Write the document a truss file describes  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The structure is walked in order and what the reader sees of each part is
;; written.  A section gives its title and its lead, the text of its public
;; block.  A member it lists is told in the words of the link that lists it,
;; when the link has some; else in its public block, or its heading when it
;; has none.  A member tagged :noexport: is left out, with what is nested
;; under it.  The result is an Org file; pandoc, when there is one, turns it
;; into Markdown.

;;; Code:

(require 'org-truss-core)

(defcustom org-truss-pandoc-program "pandoc"
  "The pandoc executable.  When it cannot be found, only the Org file is written."
  :type 'string
  :group 'org-truss)

(defcustom org-truss-pandoc-arguments
  '("--from" "org+east_asian_line_breaks" "--to" "gfm" "--wrap=none" "--standalone")
  "Arguments given to pandoc before the input file.
east_asian_line_breaks keeps a line break between two wide characters from
turning into a space, which is what Org's filled paragraphs would otherwise
do to Chinese, Japanese and Korean text."
  :type '(repeat string)
  :group 'org-truss)

(defcustom org-truss-output-extension "md"
  "Extension of the file pandoc writes, which also tells it the format."
  :type 'string
  :group 'org-truss)

;;;; Members

(defun org-truss--restatement (shown depth)
  "Return SHOWN told again, as the last item of a PREP or an SDS, at DEPTH.
SHOWN is what the reader is told of the member there, as (TITLE . BODY):
its text as a paragraph, or its title when that is all there is."
  (let ((text (if (string-empty-p (or (cdr shown) "")) (car shown) (cdr shown))))
    (and text (list (list depth (cons nil text) nil)))))

(defun org-truss--labelled (shown label)
  "Return SHOWN, (TITLE . BODY), opened with LABEL: its title, else its body."
  (cond ((or (null label) (string-empty-p label)) shown)
        ((and (car shown) (not (string-blank-p (car shown))))
         (cons (concat label (car shown)) (cdr shown)))
        (t (cons (car shown) (concat label (or (cdr shown) ""))))))

(defun org-truss--flow (member depth &optional wording label)
  "Return (DEPTH SHOWN AFTER-SUPPORT) items for MEMBER and what is under it.
SHOWN is what the reader sees: of MEMBER, as `org-truss-member-told' says,
WORDING being the words the section listing it tells it in, and opened
with LABEL when given, the role it plays in a breakdown.  It is told as
`org-truss--tell' says.  A member tagged :noexport: gives nothing, and nor
does what is nested under it."
  (unless (org-truss-noexport-p member)
    (org-truss--tell member depth wording label)))

(defun org-truss--list-items (member depth)
  "Return MEMBER's breakdown as flow items at DEPTH below it: one list."
  (let ((list (org-truss--list-text member)))
    (and (not (string-empty-p list))
         (list (list (1+ depth) (cons nil list) nil)))))

(defun org-truss--tell (member depth &optional wording label)
  "Return the flow of MEMBER at DEPTH, as it is told.
What is under it comes in the order of the file -- for a member broken
down with no reasons, as one list.  The member itself comes before all of
it or after, as its telling pattern puts it, in the words
`org-truss-member-told' gives it there, WORDING among them, and opened
with LABEL.  A pattern that closes with it again, as PREP and SDS do,
tells it once more at the end, in the words it is told in after."
  (let* ((first (org-truss-told-first-p member))
         (self (org-truss--labelled (org-truss-member-told member (if first 'before 'after) wording)
                                    label))
         (under (if (org-truss-breakdown-list member)
                    (org-truss--list-items member depth)
                  (mapcan (lambda (m)
                            (org-truss--flow m (1+ depth) nil (org-truss--role-label member m)))
                          (org-truss-member-children member)))))
    (if first
        (append (list (list depth self nil))
                under
                (and (org-truss-told-again-p member)
                     (org-truss--restatement (org-truss-member-told member 'after wording)
                                             (1+ depth))))
      (append under
              (list (list depth self (and under t)))))))

(defun org-truss--indent (text column)
  "Return TEXT with every line after the first indented COLUMN columns.
Blank lines stay blank."
  (replace-regexp-in-string "\n\\([^\n]\\)" (concat "\n" (make-string column ?\s) "\\1")
                            text t))

(defun org-truss--blocks (items)
  "Return ITEMS as blocks of text that sit inside a list item.
A heading cannot sit in a list, so a title opens its block in bold."
  (delq nil (mapcar (lambda (item)
                      (let* ((shown (nth 1 item))
                             (text (string-trim
                                    (concat (if (car shown) (format "*%s*\n" (car shown)) "")
                                            (or (cdr shown) "")))))
                        (and shown (not (string-empty-p text)) text)))
                    items)))

(defun org-truss--role-label (member child)
  "Return what opens CHILD where it is told under MEMBER, or \"\" for nothing.
When MEMBER's breakdown labels its parts, the role CHILD plays, named in
`org-truss-language': the reader is told which part of the breakdown each
piece is."
  (let ((role (org-truss-role-label-under member child)))
    (if role
        (format (org-truss--pick "%s: " "%s：") (org-truss-role-label role))
      "")))

(defun org-truss--list-marker (member child n)
  "Return (BULLET . LABEL) for CHILD, the Nth item of MEMBER's breakdown.
BULLET opens the list item, a number for a step; LABEL is the role it
plays, as `org-truss--role-label' gives it."
  (cons (if (eq (org-truss-breakdown-list member) 'numbered) (format "%d. " n) "- ")
        (org-truss--role-label member child)))

(defun org-truss--list-text (member)
  "Return MEMBER's breakdown as an Org list.
Steps are numbered and the rest are not; a part of a breakdown that labels
them opens with its role.  Each item is what the reader sees of it.  What
is nested under it goes inside its item: its own breakdown, as a list
again, or what is told under it as paragraphs.  One tagged :noexport: is
left out, and the numbers close over it."
  (let ((n 0))
    (mapconcat
     (lambda (child)
       (let* ((marker (org-truss--list-marker member child (setq n (1+ n))))
              (shown (org-truss-member-told child 'before))
              (own (string-trim (concat (cdr marker)
                                        (or (car shown) "")
                                        (if (car shown) "\n" "")
                                        (or (cdr shown) ""))))
              (nested (if (org-truss-breakdown-list child)
                          (list (org-truss--list-text child))
                        (org-truss--blocks
                         (mapcan (lambda (m) (org-truss--flow m 1 nil (org-truss--role-label child m)))
                                 (org-truss-member-children child))))))
         (concat (car marker)
                 (org-truss--indent
                  (string-join (seq-remove #'string-empty-p (cons own nested)) "\n\n")
                  (length (car marker))))))
     (seq-remove #'org-truss-noexport-p (org-truss-member-children member))
     "\n")))

(defun org-truss--emit (items level)
  "Return Org text for ITEMS inside a section whose heading is at LEVEL.
A titled member gets a heading, unless it comes after its support: there its
support would already sit under the heading before it, so its title opens
its paragraph in bold instead."
  (let (stack out)
    (dolist (item items)
      (pcase-let ((`(,depth ,public ,after) item))
        (when public
          (let ((title (car public))
                (body (cdr public)))
            (cond
             ((and title (not after))
              (while (and stack (>= (car stack) depth))
                (pop stack))
              (push (format "%s %s\n%s\n" (make-string (+ level 1 (length stack)) ?*)
                            title (if (string-empty-p body) "" (concat body "\n")))
                    out)
              (push depth stack))
             (title
              (push (format "*%s*\n%s\n" title (if (string-empty-p body) "" (concat body "\n")))
                    out))
             ((not (string-empty-p body))
              (push (concat body "\n\n") out)))))))
    (apply #'concat (nreverse out))))

;;;; Sections

(defun org-truss--render-section (model section level)
  "Return Org text for SECTION of MODEL at LEVEL, then the sections below it."
  (let ((body (cdr (org-truss-section-public section))))
    (concat
     (format "%s %s\n" (make-string level ?*) (org-truss-section-title section))
     (if (or (null body) (string-empty-p body)) "" (concat body "\n"))
     "\n"
     (org-truss--render-links model section level)
     (mapconcat (lambda (s) (org-truss--render-section model s (1+ level)))
                (org-truss-section-children section) ""))))

(defun org-truss--render-links (model section level)
  "Return Org text for the members SECTION of MODEL lists, under LEVEL."
  (mapconcat (lambda (ref)
               (let ((member (org-truss-member-by-ref model ref)))
                 (if member
                     (org-truss--emit (org-truss--flow member 1 (org-truss-section-wording
                                                                   section ref))
                                      level)
                   (format (org-truss--pick "(broken link: %s)\n\n" "（リンク切れ: %s）\n\n")
                           (org-truss--target ref)))))
             (org-truss-section-links section) ""))

(defun org-truss-render (model)
  "Return the document MODEL describes, as Org text.
The structure's own lead, the text of its public block, opens it."
  (let* ((root (org-truss-model-structure model))
         (lead (and root (cdr (org-truss-section-public root)))))
    (concat (format "#+title: %s\n#+options: toc:nil num:nil\n\n"
                    (or (org-truss-model-title model) ""))
            (if (or (null lead) (string-empty-p lead)) "" (concat lead "\n\n"))
            (if root
                (concat (org-truss--render-links model root 0)
                        (mapconcat (lambda (s) (org-truss--render-section model s 1))
                                   (org-truss-section-children root) ""))
              ""))))

;;;; Writing it out

(defun org-truss--output-base (file)
  "Return the output path for FILE without an extension."
  (expand-file-name (file-name-base file)
                    (expand-file-name org-truss-output-directory (file-name-directory file))))

(defun org-truss--pandoc (input output)
  "Convert INPUT to OUTPUT with pandoc.  Return nil, or the error text."
  (with-temp-buffer
    (let ((status (apply #'call-process org-truss-pandoc-program nil t nil
                         (append org-truss-pandoc-arguments (list input "--output" output)))))
      (unless (eq status 0)
        (string-trim (buffer-string))))))

(defconst org-truss--file-link-re
  "\\[\\[\\(file:\\|\\.\\.?/\\)\\([^]:][^]]*\\)\\]"
  "The start of a link to a file by a relative path: how it is written, the path.")

(defun org-truss--rebase-file-links (text from to)
  "Return TEXT with each link to a file by a relative path made relative to TO.
The paths are read from FROM, the directory the truss file is in, so a
picture or a source it links to is found from TO, where the document is
written.  A path past `::', a search in the file, is kept as it is."
  (replace-regexp-in-string
   org-truss--file-link-re
   (lambda (link)
     (let* ((how (match-string 1 link))
            (written (concat (if (equal how "file:") "" how) (match-string 2 link)))
            (search (string-search "::" written)))
       (save-match-data
         (let ((path (org-link-unescape (substring written 0 search))))
           (if (file-name-absolute-p path)
               link
             (format "[[file:%s%s]"
                     (org-link-escape (file-relative-name (expand-file-name path from) to))
                     (if search (substring written search) "")))))))
   text t t))

(defun org-truss-export-buffer (buffer)
  "Write the document of the truss file in BUFFER.  Return the files written.
The Org file always; the pandoc output when pandoc is found and succeeds.
A link to a file by a relative path -- a picture -- is written relative to
where the document is, so it still finds the file."
  (let* ((file (or (buffer-file-name buffer) (user-error "The truss buffer has no file")))
         (base (org-truss--output-base file))
         (org-file (concat base ".org"))
         (out-file (concat base "." org-truss-output-extension))
         (text (org-truss--rebase-file-links (org-truss-render (org-truss-read buffer))
                                  (file-name-directory file)
                                  (file-name-directory org-file))))
    (make-directory (file-name-directory org-file) t)
    (with-temp-file org-file
      (insert text))
    (if (not (executable-find org-truss-pandoc-program))
        (list org-file)
      (let ((failure (org-truss--pandoc org-file out-file)))
        (when failure
          (message "org-truss: pandoc failed: %s" failure))
        (if failure (list org-file) (list org-file out-file))))))

(defun org-truss-export ()
  "Write the document of the nearest truss file."
  (interactive)
  (let* ((file (or (org-truss-locate)
                   (user-error "No %s here or above" org-truss-file-name)))
         (written (org-truss-export-buffer (find-file-noselect file))))
    (message "org-truss: wrote %s" (mapconcat #'abbreviate-file-name written ", "))
    written))

(provide 'org-truss-export)

;;; org-truss-export.el ends here

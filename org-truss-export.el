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
;; block.  A link that tells a member, [[truss-include:m7]], is that member
;; written where it stands: its public block, or its heading when it has
;; none, then what is nested under it.  A heading tagged :noexport: is left
;; out, with what is under it.  The result is an Org file; pandoc, when there is one, turns it
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

(defvar org-truss--model nil
  "The model a document is written from, or a board drawn from, meanwhile.")

(defvar org-truss--telling nil
  "The members being told, the one telling the next: a member among them
told again would be told without end.")

(defun org-truss--loop-text (ref)
  "Return what the document says where telling REF would never end.
It names the link as text, which nothing reads as a link again."
  (format (org-truss--pick "(told without end: %s:%s)" "（展開が循環: %s:%s）")
          org-truss-include-type ref))

(defun org-truss--broken-text (target)
  "Return what the document says where a link to TARGET points to no member.
TARGET is written as text, which nothing reads as a link again."
  (format (org-truss--pick "(broken link: %s)" "（リンク切れ: %s）") target))

(defun org-truss--told-text (ref)
  "Return the heading REF told as Org text, with what is under it.
What a link [[truss-include:REF]] is written out as, wherever it is: a
member as it is told anywhere, a section as it is inside a list item --
its title in bold, its lead, then what it holds."
  (let ((heading (org-truss-heading-by-ref org-truss--model ref)))
    (cond ((null heading) (org-truss--broken-text (concat org-truss-include-type ":" ref)))
          ((memq heading org-truss--telling) (org-truss--loop-text ref))
          ((org-truss-section-p heading) (org-truss--section-text heading))
          (t (string-trim (org-truss--emit (org-truss--flow heading 1)))))))

(defun org-truss--section-text (section)
  "Return SECTION told by a link, as Org text: no heading of the document,
since it is told where the link stands, but its title in bold and its
lead, then what it holds, as inside a list item.  Nothing when it is
tagged :noexport:."
  (if (org-truss-noexport-p section)
      ""
    (let ((org-truss--telling (cons section org-truss--telling)))
      (string-join
       (append (org-truss--blocks
                (list (list 0 (cons (org-truss-section-title section)
                                    (or (cdr (org-truss-section-public section)) "")))))
               (org-truss--section-inside section))
       "\n\n"))))

(defun org-truss--pointed-text (target words)
  "Return the words a link to a member reads as in the document.
WORDS, its description, when it has one; else the heading of the member
TARGET names.  The document has no member to go to, so it is no link."
  (or words
      (let ((heading (org-truss-heading-by-ref org-truss--model (org-truss--ref target))))
        (if heading (org-truss-cluster-label heading) target))))

(defun org-truss--written (text)
  "Return TEXT as the document writes it.
A link that tells a member, [[truss-include:m7]], is that member told,
with what is nested under it, where it stands -- in a sentence too; a
link that points to one, [[#m7]], its words.  Nil stays nil."
  (and text
       (let ((from 0) out)
         (while (string-match org-truss--include-re text from)
           (let ((beg (match-beginning 0))
                 (end (match-end 0))
                 (ref (org-truss--ref (match-string 1 text))))
             (push (org-truss--pointing-written (substring text from beg)) out)
             (push (org-truss--told-text ref) out)
             (setq from end)))
         (push (org-truss--pointing-written (substring text from)) out)
         (apply #'concat (nreverse out)))))

(defun org-truss--pointing-written (text)
  "Return TEXT with each link pointing to a member as its words."
  (replace-regexp-in-string
   "\\[\\[\\([#*][^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
   (lambda (link)
     (string-match "\\[\\[\\([#*][^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]" link)
     (org-truss--pointed-text (match-string 1 link) (match-string 2 link)))
   text t t))

(defun org-truss--shown-written (shown)
  "Return SHOWN, (TITLE . BODY), as the document writes it."
  (and shown (cons (org-truss--written (car shown)) (org-truss--written (cdr shown)))))

(defun org-truss--labelled (shown label)
  "Return SHOWN, (TITLE . BODY), opened with LABEL: its title, else its body."
  (cond ((or (null label) (string-empty-p label)) shown)
        ((and (car shown) (not (string-blank-p (car shown))))
         (cons (concat label (car shown)) (cdr shown)))
        (t (cons (car shown) (concat label (or (cdr shown) ""))))))

(defun org-truss--flow (member depth &optional label)
  "Return (DEPTH SHOWN) items for MEMBER and what is under it.
SHOWN is what the reader sees: of MEMBER, as `org-truss-member-told' says,
opened with LABEL when given, the role it plays in a breakdown.  It is
told as `org-truss--tell' says.  A member tagged :noexport: gives nothing,
and nor does what is nested under it; one already being told, a note
that telling it again would never end."
  (cond ((org-truss-noexport-p member) nil)
        ((memq member org-truss--telling)
         (list (list depth (cons nil (org-truss--loop-text (org-truss-member-id member))))))
        (t (let ((org-truss--telling (cons member org-truss--telling)))
             (org-truss--tell member depth label)))))

(defun org-truss--listed-flow (cluster depth)
  "Return the flow of the members CLUSTER tells by links outside its public
block, at DEPTH, in the order of the links."
  (mapcan (lambda (ref)
            (let ((heading (org-truss-heading-by-ref org-truss--model ref)))
              (cond ((null heading)
                     (list (list depth (cons nil (org-truss--broken-text
                                                  (concat org-truss-include-type ":" ref))))))
                    ((org-truss-section-p heading)
                     (list (list depth (cons nil (if (memq heading org-truss--telling)
                                                     (org-truss--loop-text ref)
                                                   (org-truss--section-text heading))))))
                    (t (org-truss--flow heading depth)))))
          (org-truss-cluster-listed cluster)))

(defun org-truss--list-items (member depth)
  "Return what is under MEMBER as flow items at DEPTH below it: one list."
  (let ((list (org-truss--list-text member)))
    (and (not (string-empty-p list))
         (list (list (1+ depth) (cons nil list))))))

(defun org-truss--tell (member depth &optional label)
  "Return the flow of MEMBER at DEPTH, as it is told.
The member itself, in the words `org-truss-member-told' gives it, opened
with LABEL; then the members its links outside its public block tell;
then what is under it, in the order of the file -- as one list when a
pattern of MEMBER says so; see `org-truss-list-form'."
  (cons (list depth (org-truss--labelled (org-truss-member-told member) label))
        (append (org-truss--listed-flow member (1+ depth))
                (if (org-truss-list-form member)
                    (org-truss--list-items member depth)
                  (mapcan (lambda (m)
                            (org-truss--flow m (1+ depth) (org-truss--role-label member m)))
                          (org-truss-cluster-children member))))))

(defun org-truss--indent (text column)
  "Return TEXT with every line after the first indented COLUMN columns.
Blank lines stay blank."
  (replace-regexp-in-string "\n\\([^\n]\\)" (concat "\n" (make-string column ?\s) "\\1")
                            text t))

(defun org-truss--blocks (items)
  "Return ITEMS as blocks of text that sit inside a list item.
A member's title opens its block in bold, as it opens its paragraph
anywhere."
  (delq nil (mapcar (lambda (item)
                      (let* ((shown (org-truss--shown-written (nth 1 item)))
                             (text (string-trim
                                    (concat (if (car shown) (format "*%s*\n" (car shown)) "")
                                            (or (cdr shown) "")))))
                        (and shown (not (string-empty-p text)) text)))
                    items)))

(defun org-truss--role-label (member child)
  "Return what opens CHILD where it is told under MEMBER, or \"\" for nothing.
The role CHILD plays in a pattern of MEMBER whose role is flagged :label,
named in `org-truss-language': the reader is told which part of it each
piece is."
  (let ((role (org-truss-role-label-under member child)))
    (if role
        (format (org-truss--pick "%s: " "%s：") (org-truss-role-label role))
      "")))

(defun org-truss--list-marker (member child n)
  "Return (BULLET . LABEL) for CHILD, the Nth item of the list under MEMBER.
BULLET opens the list item, a number in a numbered list; LABEL is the role
it plays, as `org-truss--role-label' gives it."
  (cons (if (eq (org-truss-list-form member) 'numbered) (format "%d. " n) "- ")
        (org-truss--role-label member child)))

(defun org-truss--list-text (cluster)
  "Return what is right under CLUSTER as an Org list, numbered or not as it says.
CLUSTER is a member or a section, and what is under it members or
sections.  An item playing a role flagged :label opens with its role.
Each item is what the reader sees of it -- a section's title and lead --
and what it holds goes inside it: the members its links tell, then what
is nested under a member, as a list again when it says so, else as
paragraphs; the sections below a section, as `org-truss--section-inside'
says.  One tagged :noexport: is left out, and the numbers close over it."
  (let ((n 0))
    (mapconcat
     (lambda (child)
       (let* ((marker (org-truss--list-marker cluster child (setq n (1+ n))))
              (section (org-truss-section-p child))
              (shown (org-truss--shown-written
                      (if section
                          (cons (org-truss-section-title child) (cdr (org-truss-section-public child)))
                        (org-truss-member-told child))))
              (own (string-trim (concat (cdr marker)
                                        (or (car shown) "")
                                        (if (car shown) "\n" "")
                                        (or (cdr shown) ""))))
              (nested (cond (section (org-truss--section-inside child))
                            (t (let ((org-truss--telling (cons child org-truss--telling)))
                                 (append (org-truss--blocks (org-truss--listed-flow child 1))
                                         (if (org-truss-list-form child)
                                             (list (org-truss--list-text child))
                                           (org-truss--blocks
                                            (mapcan (lambda (m)
                                                      (org-truss--flow m 1 (org-truss--role-label child m)))
                                                    (org-truss-cluster-children child))))))))))
         (concat (car marker)
                 (org-truss--indent
                  (string-join (seq-remove #'string-empty-p (cons own nested)) "\n\n")
                  (length (car marker))))))
     (seq-remove #'org-truss-noexport-p (org-truss-cluster-children cluster))
     "\n")))

(defun org-truss--section-inside (section)
  "Return what SECTION holds as blocks that sit inside a list item.
The members its links tell, then the sections below it: as a list when
its pattern says so, else each as its title in bold, its lead, and what
it holds in turn."
  (append
   (org-truss--blocks (org-truss--listed-flow section 1))
   (if (org-truss-list-form section)
       (let ((list (org-truss--list-text section)))
         (and (not (string-empty-p list)) (list list)))
     (mapcan (lambda (s)
               (append (org-truss--blocks
                        (list (list 0 (cons (org-truss-section-title s)
                                            (or (cdr (org-truss-section-public s)) "")))))
                       (org-truss--section-inside s)))
             (seq-remove #'org-truss-noexport-p (org-truss-section-children section))))))

(defun org-truss--emit (items)
  "Return Org text for ITEMS, each a paragraph.
A member's title opens its paragraph in bold: a heading of the document is
a section's alone."
  (mapconcat (lambda (item)
               (pcase-let* ((`(,_depth ,public) item)
                            (`(,title . ,body) (org-truss--shown-written public)))
                 (cond ((null public) "")
                       (title (format "*%s*\n%s\n" title
                                      (if (string-empty-p (or body "")) "" (concat body "\n"))))
                       ((string-empty-p (or body "")) "")
                       (t (concat body "\n\n")))))
             items ""))

;;;; Sections

(defun org-truss--render-section (section level)
  "Return Org text for SECTION at LEVEL, then the sections below it."
  (let ((body (org-truss--written (cdr (org-truss-section-public section)))))
    (concat
     (format "%s %s\n" (make-string level ?*) (org-truss--written (org-truss-section-title section)))
     (if (or (null body) (string-empty-p body)) "" (concat body "\n"))
     "\n"
     (org-truss--emit (org-truss--listed-flow section 1))
     (org-truss--render-below section (1+ level)))))

(defun org-truss--render-below (section level)
  "Return Org text for the sections below SECTION.
As one list when a pattern of SECTION says so, as what is under a member
is; see `org-truss-list-form'.  Else each under a heading at LEVEL.  One
tagged :noexport: is left out, with what is under it, as a member is."
  (if (org-truss-list-form section)
      (let ((list (org-truss--list-text section)))
        (if (string-empty-p list) "" (concat list "\n\n")))
    (mapconcat (lambda (s) (org-truss--render-section s level))
               (seq-remove #'org-truss-noexport-p (org-truss-section-children section)) "")))

(defun org-truss-render (model)
  "Return the document MODEL describes, as Org text.
Under the title `org-truss-document-title' gives it, the structure's own
lead, the text of its public block, opens it; then the members its links
tell, and the sections below it."
  (let* ((org-truss--model model)
         (org-truss--telling nil)
         (root (org-truss-model-structure model))
         (lead (and root (org-truss--written (cdr (org-truss-section-public root))))))
    (concat (format "#+title: %s\n#+options: toc:nil num:nil\n\n"
                    (or (org-truss--written (org-truss-document-title model)) ""))
            (if (or (null lead) (string-empty-p lead)) "" (concat lead "\n\n"))
            (if root
                (concat (org-truss--emit (org-truss--listed-flow root 1))
                        (org-truss--render-below root 1))
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

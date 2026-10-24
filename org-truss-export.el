;;; org-truss-export.el --- Write the document a truss file describes  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The structure is walked in order and what the reader sees of each part is
;; written.  A heading of the file is told by its words and the text under
;; it, a comment left out: a section is a heading of the document, its
;; title, its lead, then the sections below it, a level down.
;; A link that tells a heading, [[truss-include:m7]], is told by where it
;; stands.  On a heading's line it is that heading of the document: its
;; words, then what follows them -- its text, then what is under it, a
;; level down.  In text it is its words, in the sentence, and what follows
;; them comes after the paragraph or the list item, as a list one level in.
;; Once a list, what is under it stays a list; so too under a pattern that
;; lists what is under it, and below the deepest level of headings.  A
;; heading tagged :noexport: is left out, with what is under it.  The result
;; is an Org file; pandoc, when there is one, turns it into Markdown.

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

;;;; Telling

(defvar org-truss--model nil
  "The model a document is written from, or a board drawn from, meanwhile.")

(defvar org-truss--telling nil
  "The headings being told, the one telling the next: one among them told
again would be told without end.")

(defconst org-truss--deepest-level 6
  "The deepest level of the document's headings: Markdown has no seventh.
What is under a heading there is a list.")

(defconst org-truss--bullet-re "^[ \t]*\\(?:[-+]\\|[0-9]+[.)]\\)[ \t]+"
  "The start of a list item, to where its words begin.")

(defun org-truss--loop-text (ref)
  "Return what the document says where telling REF would never end.
It names the link as text, which nothing reads as a link again."
  (format (org-truss--pick "(told without end: %s:%s)" "（展開が循環: %s:%s）")
          org-truss-include-type ref))

(defun org-truss--broken-text (target)
  "Return what the document says where a link to TARGET points to no member.
TARGET is written as text, which nothing reads as a link again."
  (format (org-truss--pick "(broken link: %s)" "（リンク切れ: %s）") target))

(defun org-truss--present-p (text)
  "Non-nil when TEXT has words."
  (and text (not (string-blank-p text))))

(defun org-truss--join (texts)
  "Return TEXTS that have words, a blank line apart.
Each without the blank lines around it; its first line keeps its indent."
  (string-join (mapcar (lambda (text) (string-trim text "\\(?:[ \t]*\n\\)+" "[ \t\n]+"))
                       (seq-filter #'org-truss--present-p texts))
               "\n\n"))

(defun org-truss--indent (text column)
  "Return TEXT with every line after the first indented COLUMN columns.
Blank lines stay blank."
  (replace-regexp-in-string "\n\\([^\n]\\)" (concat "\n" (make-string column ?\s) "\\1")
                            text t))

(defun org-truss--shown (cluster)
  "Return what the reader sees of CLUSTER, as (TITLE . BODY), or nil for nothing.
Its heading as its title, and the text under it outside the comments.
Nothing when it is tagged :noexport:."
  (and (not (org-truss-noexport-p cluster))
       (cons (org-truss-cluster-label cluster) (org-truss-cluster-body cluster))))

(defun org-truss--words (shown)
  "Return the words SHOWN, (TITLE . BODY), stands as where it is told:
its title, else its body."
  (if (org-truss--present-p (car shown)) (car shown) (or (cdr shown) "")))

(defun org-truss--labelled (shown label)
  "Return SHOWN, (TITLE . BODY), opened with LABEL: its title, else its body."
  (cond ((or (null label) (string-empty-p label)) shown)
        ((org-truss--present-p (car shown))
         (cons (concat label (car shown)) (cdr shown)))
        (t (cons (car shown) (concat label (or (cdr shown) ""))))))

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

(defun org-truss--told (cluster label tell)
  "Return what TELL says of CLUSTER, while CLUSTER is being told.
TELL is called with what the reader sees of it, opened with LABEL; see
`org-truss--shown'.  Nil when the reader sees nothing of it; where it is
already being told, the note that telling it would never end."
  (let ((shown (org-truss--shown cluster)))
    (cond ((null shown) nil)
          ((memq cluster org-truss--telling)
           (org-truss--loop-text (or (org-truss-cluster-id cluster) (org-truss-cluster-label cluster))))
          (t (let ((org-truss--telling (cons cluster org-truss--telling)))
               (funcall tell (org-truss--labelled shown label)))))))

(defun org-truss--rest (cluster shown level)
  "Return what follows CLUSTER's words where it is told, as Org text.
SHOWN is what the reader sees of it, as `org-truss--shown' says.  Its
body, when its title is its words; then what is under it, as
`org-truss--under' says at LEVEL."
  (org-truss--join
   (list (and (org-truss--present-p (car shown)) (org-truss--written (cdr shown)))
         (org-truss--under cluster level))))

(defun org-truss--under (cluster level)
  "Return what is under CLUSTER as Org text, one tagged :noexport: left out.
Each under a heading one level below LEVEL; as a list instead when LEVEL
is nil, CLUSTER being told in a list, when it is the deepest level, or
when a pattern of CLUSTER says so -- see `org-truss-list-form'."
  (let ((children (seq-remove #'org-truss-noexport-p (org-truss-cluster-children cluster))))
    (if (or (null level) (>= level org-truss--deepest-level) (org-truss-list-form cluster))
        (org-truss--list cluster children)
      (org-truss--join (mapcar (lambda (child)
                                 (org-truss--heading child (1+ level)
                                                     (org-truss--role-label cluster child)))
                               children)))))

(defun org-truss--list (cluster children)
  "Return CHILDREN, what is under CLUSTER, as an Org list.
Numbered or not as CLUSTER says, the numbers running over CHILDREN alone."
  (let ((n 0))
    (mapconcat (lambda (child)
                 (let ((marker (org-truss--list-marker cluster child (setq n (1+ n)))))
                   (org-truss--list-item child (car marker) (cdr marker))))
               children "\n")))

(defun org-truss--heading (cluster level &optional label)
  "Return CLUSTER told under a heading of the document at LEVEL, opened with LABEL.
Its words are the heading, and what follows them comes under it, a level
down; see `org-truss--rest'.  Without a title it is no heading: its body
is a paragraph, and what follows it a list."
  (or (org-truss--told
       cluster label
       (lambda (shown)
         (if (org-truss--present-p (car shown))
             (org-truss--join (list (org-truss--heading-line (car shown) level)
                                    (org-truss--rest cluster shown level)))
           (org-truss--join (list (org-truss--written (cdr shown))
                                  (org-truss--rest cluster shown nil))))))
      ""))

(defun org-truss--heading-line (title level)
  "Return TITLE as a heading of the document at LEVEL, as Org text.
A link in it that tells a heading is that heading's words there, and what
follows them comes under it, a level down."
  (pcase-let ((`(,words . ,after) (org-truss--inline title level)))
    (org-truss--join
     (list (concat (make-string level ?*) " "
                   (replace-regexp-in-string "[ \t]*\n[ \t\n]*" " " (string-trim words)))
           after))))

(defun org-truss--list-item (cluster bullet &optional label)
  "Return CLUSTER told as an item of a list, opened by BULLET and LABEL.
Its words open the item, and what follows them goes inside it, as a list
again; see `org-truss--rest'."
  (concat bullet
          (org-truss--indent
           (or (org-truss--told
                cluster label
                (lambda (shown)
                  (org-truss--join (list (org-truss--written (org-truss--words shown))
                                         (org-truss--rest cluster shown nil)))))
               "")
           (length bullet))))

(defun org-truss--pointed-text (target words)
  "Return the words a link to a member reads as in the document.
WORDS, its description, when it has one; else the heading of the member
TARGET names.  The document has no member to go to, so it is no link."
  (or words
      (let ((heading (org-truss-heading-by-ref org-truss--model (org-truss--ref target))))
        (if heading (org-truss-cluster-label heading) target))))

(defun org-truss--pointing-written (text)
  "Return TEXT with each link pointing to a member as its words."
  (replace-regexp-in-string
   "\\[\\[\\([#*][^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
   (lambda (link)
     (string-match "\\[\\[\\([#*][^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]" link)
     (org-truss--pointed-text (match-string 1 link) (match-string 2 link)))
   text t t))

(defun org-truss--inline (text level &optional column)
  "Return (WORDS . AFTER) for TEXT, a sentence or the words of a heading.
WORDS is TEXT as the document writes it: each link that tells a heading,
[[truss-include:m7]], as that heading's words -- its description, when
it has one, the lines after its first indented COLUMN columns, where the
words of TEXT begin -- and each link that points to one, [[#m7]], as its
words.
AFTER is what follows the words of those it tells, in order, as Org
text: what is under them under headings below LEVEL, or as a list when
LEVEL is nil or the one told has no title."
  (let ((text (or text ""))
        (from 0) words after)
    (while (string-match org-truss--include-re text from)
      (let ((beg (match-beginning 0))
            (end (match-end 0))
            (ref (org-truss--ref (match-string 1 text)))
            (given (match-string 2 text)))
        (push (org-truss--pointing-written (substring text from beg)) words)
        (pcase-let ((`(,told . ,rest) (org-truss--told-inline ref given level)))
          (push (org-truss--indent told (or column 0)) words)
          (push rest after))
        (setq from end)))
    (push (org-truss--pointing-written (substring text from)) words)
    (cons (apply #'concat (nreverse words)) (org-truss--join (nreverse after)))))

(defun org-truss--told-inline (ref given level)
  "Return (WORDS . AFTER) for the heading REF a link tells, GIVEN its description.
See `org-truss--inline'."
  (let* ((heading (org-truss-heading-by-ref org-truss--model ref))
         (told (if (null heading)
                   (org-truss--broken-text (concat org-truss-include-type ":" ref))
                 (org-truss--told
                  heading nil
                  (lambda (shown)
                    (pcase-let ((`(,words . ,after)
                                 (if (org-truss--present-p given)
                                     (list given)
                                   (org-truss--inline (org-truss--words shown) level))))
                      (cons words (org-truss--join
                                   (list after (org-truss--rest heading shown
                                                                (and (org-truss--present-p (car shown))
                                                                     level)))))))))))
    (if (consp told) told (cons (or told "") nil))))

(defun org-truss--written (text)
  "Return TEXT as the document writes it, a block at a time.
A block is a paragraph or a list item.  Its links are written as
`org-truss--inline' says, and what follows the words of the headings it
tells comes after it, as a list where its words begin: one level in, for
a list item.  Nil is \"\"."
  (let (out block column)
    (cl-flet ((finish ()
                (when block
                  (pcase-let ((`(,words . ,after)
                               (org-truss--inline (string-join (reverse block) "\n") nil column)))
                    (push (if (string-empty-p after)
                              words
                            (concat words "\n\n" (make-string column ?\s)
                                    (org-truss--indent after column)))
                          out))
                  (setq block nil))))
      (dolist (line (split-string (or text "") "\n"))
        (cond ((string-blank-p line)
               (finish)
               (push "" out))
              ((string-match org-truss--bullet-re line)
               (let ((start (match-end 0)))
                 (finish)
                 (setq column start))
               (push line block))
              (t (unless block
                   (setq column (progn (string-match "\\`[ \t]*" line) (match-end 0))))
                 (push line block))))
      (finish))
    (string-join (nreverse out) "\n")))

(defun org-truss-render (model)
  "Return the document MODEL describes, as Org text.
Under the title `org-truss-document-title' gives it, the structure's own
lead, the text under its heading, opens it; then what follows it, as
`org-truss--rest' says, the sections below it under headings from the
first level."
  (let* ((org-truss--model model)
         (org-truss--telling nil)
         (root (org-truss-model-structure model))
         (shown (and root (org-truss--shown root)))
         (text (if shown (org-truss--rest root shown 0) "")))
    (concat (format "#+title: %s\n#+options: toc:nil num:nil\n\n"
                    (car (org-truss--inline (org-truss-document-title model) nil)))
            (if (string-empty-p text) "" (concat text "\n")))))

;;;; Writing it out

(defun org-truss--output-base (file)
  "Return the output path for FILE without an extension."
  (expand-file-name (file-name-base file)
                    (expand-file-name org-truss-output-directory (file-name-directory file))))

(defun org-truss--pandoc (input output)
  "Convert INPUT to OUTPUT with pandoc.  Return nil, or the error text.
Run in INPUT's directory and given the two names alone: `call-process'
encodes its arguments with the process coding system, and on Windows a
UTF-8 one turns a Japanese directory name into one pandoc cannot open."
  (with-temp-buffer
    (let* ((default-directory (file-name-directory input))
           (coding-system-for-read 'utf-8)
           (status (apply #'call-process org-truss-pandoc-program nil t nil
                          (append org-truss-pandoc-arguments
                                  (list (file-relative-name input)
                                        "--output" (file-relative-name output))))))
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

(defvar org-truss-moor-export-function nil
  "Function writing a `moor:' link as the reader is to follow it, or nil.
Called with the link's path, its words or nil, and the truss file; returns
what the document says in its place.  Set by org-truss-moor.el; without
org-moor a `moor:' link is written as it is.")

(defconst org-truss--moor-link-re
  "\\[\\[moor:\\([^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
  "A `moor:' link: its path, the id and any place, and its words.")

(defun org-truss--export-moor-links (text file)
  "Return TEXT with each `moor:' link written for the reader of FILE's document.
The copy a link opens is the writer's; the reader is sent where the source
came from, by `org-truss-moor-export-function'."
  (if (not org-truss-moor-export-function)
      text
    (replace-regexp-in-string
     org-truss--moor-link-re
     (lambda (link)
       (let ((path (match-string 1 link))
             (words (match-string 2 link)))
         (save-match-data
           (funcall org-truss-moor-export-function path words file))))
     text t t)))

(defun org-truss-export-buffer (buffer)
  "Write the document of the truss file in BUFFER.  Return the files written.
The Org file always; the pandoc output when pandoc is found and succeeds.
A link to a file by a relative path -- a picture -- is written relative to
where the document is, so it still finds the file; a `moor:' link goes
where its source came from."
  (let* ((file (or (buffer-file-name buffer) (user-error "The truss buffer has no file")))
         (base (org-truss--output-base file))
         (org-file (concat base ".org"))
         (out-file (concat base "." org-truss-output-extension))
         (text (org-truss--rebase-file-links
                (org-truss--export-moor-links (org-truss-render (org-truss-read buffer)) file)
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

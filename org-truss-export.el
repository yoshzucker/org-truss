;;; org-truss-export.el --- Write the output document of a truss file  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Structure is walked in order and what the output document shows of each
;; member is written: its words, then its text, a comment left out.  A
;; member of Structure is a heading of the output document, and its
;; supporting members are headings a level down.
;; An include link, [[truss-include:m7]], includes m7 where it stands.  As
;; the words of a member it is that member there: m7's words, then its
;; text and its supporting members.  In text it is m7's words, in the
;; sentence, and what follows them comes after the paragraph or the list
;; item, as a list one level in.
;; Once a list, what is under it stays a list; so too the supporting
;; members of a logic or breakdown truss, and below the deepest level of
;; headings.  A member tagged :noexport: is left out, with what is under
;; it.  The result is an Org file; pandoc, when there is one, turns it into
;; Markdown.

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

;;;; The output document

(defvar org-truss--model nil
  "The model an output document is written from, or a board drawn from, meanwhile.")

(defvar org-truss--writing nil
  "The members being written, each including the next: one among them
included again would be written without end.")

(defconst org-truss--deepest-level 6
  "The deepest level of the output document's headings: Markdown has no seventh.
What is under a heading there is a list.")

(defconst org-truss--bullet-re "^[ \t]*\\(?:[-+]\\|[0-9]+[.)]\\)[ \t]+"
  "The start of a list item, to where its words begin.")

(defun org-truss--loop-text (id)
  "Return what the output document says where including ID would never end.
It names the link as text, which nothing reads as a link again."
  (format (org-truss--pick "(included without end: %s:%s)" "（展開が循環: %s:%s）")
          org-truss-include-type id))

(defun org-truss--broken-text (target)
  "Return what the output document says where a link to TARGET finds no member.
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

(defun org-truss--output-words (output)
  "Return the words OUTPUT, (WORDS . BODY), stands as where it is written:
its words, else its body."
  (if (org-truss--present-p (car output)) (car output) (or (cdr output) "")))

(defun org-truss--opened (output label)
  "Return OUTPUT, (WORDS . BODY), opened with LABEL: its words, else its body."
  (cond ((or (null label) (string-empty-p label)) output)
        ((org-truss--present-p (car output))
         (cons (concat label (car output)) (cdr output)))
        (t (cons (car output) (concat label (or (cdr output) ""))))))

(defun org-truss--role-opening (apex support)
  "Return what opens SUPPORT, a supporting member of APEX, or \"\" for nothing.
The role SUPPORT plays in a pattern of APEX whose role is flagged :label,
named in `org-truss-language': the reader is told which part of it each
piece is."
  (let ((role (org-truss-labelling-role apex support)))
    (if role
        (format (org-truss--pick "%s: " "%s：") (org-truss-role-label role))
      "")))

(defun org-truss--list-marker (apex support n)
  "Return (BULLET . LABEL) for SUPPORT, the Nth item of APEX's list.
BULLET opens the list item, a number in a numbered list; LABEL is the role
it plays, as `org-truss--role-opening' gives it."
  (cons (if (eq (org-truss-list-form apex) 'numbered) (format "%d. " n) "- ")
        (org-truss--role-opening apex support)))

(defun org-truss--write (member label write)
  "Return what WRITE says of MEMBER, while MEMBER is being written.
WRITE is called with what the output document shows of it, opened with
LABEL; see `org-truss-member-output'.  Nil when it shows nothing of it;
where it is already being written, the note that including it would
never end."
  (let ((output (org-truss-member-output member)))
    (cond ((null output) nil)
          ((memq member org-truss--writing)
           (org-truss--loop-text (or (org-truss-member-id member) (org-truss-member-words member))))
          (t (let ((org-truss--writing (cons member org-truss--writing)))
               (funcall write (org-truss--opened output label)))))))

(defun org-truss--after-words (member output level)
  "Return what follows MEMBER's words where it is written, as Org text.
OUTPUT is what the output document shows of it.  Its body, when its words
are words; then its supporting members, as `org-truss--supports-text'
says at LEVEL.  Where its text holds lists of its supporting members,
each is written where the list is, between the pieces of the body; see
`org-truss-member-pieces'."
  (let ((pieces (org-truss-member-pieces member)))
    (if (not (and pieces (org-truss--present-p (car output))))
        (org-truss--join
         (list (and (org-truss--present-p (car output)) (org-truss--written (cdr output)))
               (org-truss--supports-text member level)))
      (let ((supports (org-truss-member-supports member))
            written)
        (while pieces
          (pcase-let ((`(,text . ,n) (pop pieces)))
            (push (org-truss--written text) written)
            (when n
              ;; The last list with no text after it takes the members
              ;; written as headings too, which follow its items: one
              ;; list, numbered on.
              (when (and (not (seq-some #'car pieces)) (not (seq-some #'cdr pieces)))
                (setq n (length supports)))
              ;; Org has no text of a heading after the headings under
              ;; it: what text follows is written after a list.
              (push (org-truss--supports-text member (and (not (seq-some #'car pieces)) level)
                                              (seq-take supports n))
                    written)
              (setq supports (nthcdr n supports)))))
        (when supports
          (push (org-truss--supports-text member level supports) written))
        (org-truss--join (nreverse written))))))

(defun org-truss--supports-text (member level &optional supports)
  "Return MEMBER's supporting members as Org text, one tagged :noexport: left out.
Each a heading one level below LEVEL; as a list instead when LEVEL is
nil, MEMBER being written in a list, when it is the deepest level, or
when a pattern of MEMBER says so -- see `org-truss-list-form'.  SUPPORTS,
if given, are those of them to write."
  (let ((supports (seq-remove #'org-truss-noexport-p
                              (or supports (org-truss-member-supports member)))))
    (if (or (null level) (>= level org-truss--deepest-level) (org-truss-list-form member))
        (org-truss--supports-list member supports)
      (org-truss--join (mapcar (lambda (support)
                                 (org-truss--as-heading support (1+ level)
                                                        (org-truss--role-opening member support)))
                               supports)))))

(defun org-truss--supports-list (apex supports)
  "Return SUPPORTS, supporting members of APEX, as an Org list.
Numbered or not as APEX says, the numbers running over SUPPORTS alone."
  (let ((n 0))
    (mapconcat (lambda (support)
                 (let ((marker (org-truss--list-marker apex support (setq n (1+ n)))))
                   (org-truss--as-item support (car marker) (cdr marker))))
               supports "\n")))

(defun org-truss--as-heading (member level &optional label)
  "Return MEMBER as a heading of the output document at LEVEL, opened with LABEL.
Its words are the heading, and what follows them comes under it, a level
down; see `org-truss--after-words'.  Without words it is no heading: its
body is a paragraph, and what follows it a list."
  (or (org-truss--write
       member label
       (lambda (output)
         (if (org-truss--present-p (car output))
             (org-truss--join (list (org-truss--heading-line (car output) level)
                                    (org-truss--after-words member output level)))
           (org-truss--join (list (org-truss--written (cdr output))
                                  (org-truss--after-words member output nil))))))
      ""))

(defun org-truss--heading-line (words level)
  "Return WORDS as a heading of the output document at LEVEL, as Org text.
An include link in them is the included member's words there, and what
follows those comes under it, a level down."
  (pcase-let ((`(,written . ,after) (org-truss--inline words level)))
    (org-truss--join
     (list (concat (make-string level ?*) " "
                   (replace-regexp-in-string "[ \t]*\n[ \t\n]*" " " (string-trim written)))
           after))))

(defun org-truss--as-item (member bullet &optional label)
  "Return MEMBER as an item of a list, opened by BULLET and LABEL.
Its words open the item, and what follows them goes inside it, as a list
again; see `org-truss--after-words'."
  (concat bullet
          (org-truss--indent
           (or (org-truss--write
                member label
                (lambda (output)
                  (org-truss--join (list (org-truss--written (org-truss--output-words output))
                                         (org-truss--after-words member output nil)))))
               "")
           (length bullet))))

(defun org-truss--pointed-text (target words)
  "Return the words a pointing link reads as in the output document.
WORDS, its description, when it has one; else the words of the member
TARGET names.  The output document has no member to go to, so it is no
link."
  (or words
      (let ((member (org-truss-member-by-id org-truss--model (org-truss--link-id target))))
        (if member (org-truss-member-words member) target))))

(defconst org-truss--pointing-words-re
  "\\[\\[\\([#*][^]\n]+\\|[[:alnum:]_-]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
  "A pointing link, as `org-truss--pointing-re' reads one: its target, and
its description.")

(defun org-truss--pointing-written (text)
  "Return TEXT with each pointing link as its words."
  (replace-regexp-in-string
   org-truss--pointing-words-re
   (lambda (link)
     (string-match org-truss--pointing-words-re link)
     (org-truss--pointed-text (match-string 1 link) (match-string 2 link)))
   text t t))

(defun org-truss--inline (text level &optional column)
  "Return (WORDS . AFTER) for TEXT, a sentence or the words of a member.
WORDS is TEXT as the output document writes it: each include link,
[[truss-include:m7]], as m7's words -- its description, when it has one,
the lines after its first indented COLUMN columns, where the words of
TEXT begin -- and each pointing link, [[#m7]], as its words.
AFTER is what follows the words of the members it includes, in order, as
Org text: their supporting members as headings below LEVEL, or as a list
when LEVEL is nil or the one included has no words."
  (let ((text (or text ""))
        (from 0) words after)
    (while (string-match org-truss--include-re text from)
      (let ((beg (match-beginning 0))
            (end (match-end 0))
            (id (org-truss--link-id (match-string 1 text)))
            (given (match-string 2 text)))
        (push (org-truss--pointing-written (substring text from beg)) words)
        (pcase-let ((`(,written . ,rest) (org-truss--included-inline id given level)))
          (push (org-truss--indent written (or column 0)) words)
          (push rest after))
        (setq from end)))
    (push (org-truss--pointing-written (substring text from)) words)
    (cons (apply #'concat (nreverse words)) (org-truss--join (nreverse after)))))

(defun org-truss--included-inline (id given level)
  "Return (WORDS . AFTER) for the member ID an include link includes.
GIVEN is the link's description; see `org-truss--inline'."
  (let* ((member (org-truss-member-by-id org-truss--model id))
         (written (if (null member)
                      (org-truss--broken-text (concat org-truss-include-type ":" id))
                    (org-truss--write
                     member nil
                     (lambda (output)
                       (pcase-let ((`(,words . ,after)
                                    (if (org-truss--present-p given)
                                        (list given)
                                      (org-truss--inline (org-truss--output-words output) level))))
                         (cons words (org-truss--join
                                      (list after (org-truss--after-words
                                                   member output
                                                   (and (org-truss--present-p (car output))
                                                        level)))))))))))
    (if (consp written) written (cons (or written "") nil))))

(defun org-truss--written (text)
  "Return TEXT as the output document writes it, a block at a time.
A block is a paragraph or a list item.  Its links are written as
`org-truss--inline' says, and what follows the words of the members it
includes comes after it, as a list where its words begin: one level in,
for a list item.  Nil is \"\"."
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

(defun org-truss-render-document (model)
  "Return the output document MODEL describes, as Org text.
Under the title `org-truss-document-title' gives it, Structure's own
text opens it; then what follows it, as `org-truss--after-words' says,
Structure's members as headings from the first level."
  (let* ((org-truss--model model)
         (org-truss--writing nil)
         (root (org-truss-model-structure model))
         (output (and root (org-truss-member-output root)))
         (text (if output (org-truss--after-words root output 0) "")))
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
picture or a source it links to is found from TO, where the output
document is written.  A path past `::', a search in the file, is kept as
it is."
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
what the output document says in its place.  Set by org-truss-moor.el;
without org-moor a `moor:' link is written as it is.")

(defconst org-truss--moor-link-re
  "\\[\\[moor:\\([^]\n]+\\)\\]\\(?:\\[\\([^]\n]*\\)\\]\\)?\\]"
  "A `moor:' link: its path, the id and any place, and its words.")

(defun org-truss--export-moor-links (text file)
  "Return TEXT with each `moor:' link written for the reader.
For the reader of FILE's output document.  The copy a link opens is the
writer's; the reader is sent where the source came from, by
`org-truss-moor-export-function'."
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
  "Write the output document of the truss file in BUFFER.
Return the files written: the Org file always; the pandoc output when
pandoc is found and succeeds.  A link to a file by a relative path -- a
picture -- is written relative to where the output document is, so it
still finds the file; a `moor:' link goes where its source came from."
  (let* ((file (or (buffer-file-name buffer) (user-error "The truss buffer has no file")))
         (base (org-truss--output-base file))
         (org-file (concat base ".org"))
         (out-file (concat base "." org-truss-output-extension))
         (text (org-truss--rebase-file-links
                (org-truss--export-moor-links (org-truss-render-document (org-truss-read buffer)) file)
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
  "Write the output document of the nearest truss file."
  (interactive)
  (let* ((file (or (org-truss-locate)
                   (user-error "No %s here or above" org-truss-file-name)))
         (written (org-truss-export-buffer (find-file-noselect file))))
    (message "org-truss: wrote %s" (mapconcat #'abbreviate-file-name written ", "))
    written))

(provide 'org-truss-export)

;;; org-truss-export.el ends here

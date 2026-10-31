;;; org-truss-edit.el --- The edits made to a truss file  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The edits org-truss makes to a truss file, each at a position in its
;; buffer: Structure's members rearranged, include links, roles and grounds
;; written, members added, moved and deleted.  The board's commands make
;; them.  What is read from the file is in org-truss-core.el.

;;; Code:

(require 'org-truss-core)

;;;; A member and what is under it, as written

(defconst org-truss--heading-term-re
  "\\(?:<<[^<>\n]+>>\\)?\\([^ \t\n:][^\n]*?\\)[ \t]+::\\(?:[ \t]+\\|$\\)"
  "The term before :: at the start of a heading's words, group 1, and the
:: after it.")

;; Edits that rearrange Structure's members read a subtree into a
;; snapshot, change the snapshot, and write the subtree back.  A snapshot
;; keeps what it does not understand -- its text, other drawers -- as
;; written.

(defun org-truss--snapshot (pos)
  "Return a snapshot of the subtree at POS.
A plist of :heading (the text after the stars), :props, :drawers, :all
\(its text, comments and all), :include-lines (the IDs included on lines
of their own) and :children, the snapshots of the headings under it."
  (let ((parsed (org-truss--text-at pos)))
    (save-excursion
      (goto-char pos)
      (looking-at "\\*+[ \t]+\\(.*\\)$")
      (list :heading (match-string-no-properties 1)
            :props (plist-get parsed :props)
            :drawers (plist-get parsed :drawers)
            :all (plist-get parsed :all)
            :include-lines (plist-get parsed :include-lines)
            :children (mapcar #'org-truss--snapshot (org-truss--child-headings pos))))))

(defun org-truss--snapshot-telling-role (snapshot)
  "Return the role SNAPSHOT's TRUSS_TELLING_ROLE names, or the term before
:: in its heading names, or nil."
  (or (org-truss--intern (cdr (assoc (org-truss-role-property 'telling) (plist-get snapshot :props))))
      (let ((heading (plist-get snapshot :heading)))
        (and (string-match (concat "\\`" org-truss--heading-term-re) heading)
             (let ((term (org-truss--intern (match-string 1 heading))))
               (and (assq term (org-truss-pattern-roles-all)) term))))))

(defun org-truss--drawer (props)
  "Return the property drawer for PROPS, an alist, or \"\" when it is empty."
  (if (null props)
      ""
    (concat ":PROPERTIES:\n"
            (mapconcat (lambda (p) (format ":%s: %s\n" (car p) (cdr p))) props "")
            ":END:\n")))

(defun org-truss--trim-blank-lines (text)
  "Return TEXT without blank lines at either end, ending in a newline if not empty."
  (let ((s (string-trim text "\\(?:[ \t]*\n\\)*" "[ \t\n]*")))
    (if (string-empty-p s) "" (concat s "\n"))))

(defun org-truss--serialize (snapshot level)
  "Return SNAPSHOT written out as a subtree whose top heading is at LEVEL."
  (concat (make-string level ?*) " " (plist-get snapshot :heading) "\n"
          (org-truss--drawer (plist-get snapshot :props))
          (plist-get snapshot :drawers)
          (org-truss--trim-blank-lines (plist-get snapshot :all))
          (mapconcat #'org-truss--include-item (plist-get snapshot :include-lines) "")
          "\n"
          (mapconcat (lambda (c) (org-truss--serialize c (1+ level)))
                     (plist-get snapshot :children) "")))

(defun org-truss--include-item (id)
  "Return the list item holding the include link of ID."
  (format "- %s\n" (org-truss--include-link id)))

(defun org-truss--replace-subtree (pos text)
  "Replace the subtree at POS with TEXT."
  (save-excursion
    (goto-char pos)
    (let ((end (save-excursion (org-end-of-subtree t t) (point))))
      (delete-region pos end)
      (goto-char pos)
      (insert text))))

(defun org-truss--level (pos)
  "Return the level of the heading at POS."
  (org-with-point-at pos (org-current-level)))

(defun org-truss--set-prop (props key value)
  "Return PROPS with KEY set to VALUE, or removed when VALUE is nil."
  (let ((rest (seq-remove (lambda (p) (equal (car p) key)) props)))
    (if value
        (if (assoc key props)
            (mapcar (lambda (p) (if (equal (car p) key) (cons key value) p)) props)
          (append rest (list (cons key value))))
      rest)))

(defun org-truss--role-snapshot (role)
  "Return a snapshot of a new heading playing ROLE, a (ROLE . FLAGS), of a telling.
The role named before ::, its words the role's."
  (list :heading (format "%s :: %s" (car role) (org-truss-role-label (car role)))
        :props nil :drawers "" :all "" :include-lines nil :children nil))

(defun org-truss-apply-telling (pos pattern)
  "Give the member at POS the telling PATTERN, and a member for each role.
A heading already under it whose TRUSS_TELLING_ROLE is one of the
pattern's roles takes that role as it is -- words, roles and all it
holds -- so nothing written is changed; a heading for the role, its words
the role's in `org-truss-language', is added only where none does.  A
heading playing none of the roles is kept after the rest -- outside the
pattern, to be moved by hand.  The include links of the member itself
stay on it."
  (let* ((news (mapcar #'org-truss--role-snapshot (org-truss-pattern-roles pattern)))
         (snapshot (org-truss--snapshot pos))
         (olds (plist-get snapshot :children))
         (role-of (lambda (old)
                    (let ((role (org-truss--snapshot-telling-role old)))
                      (and role (seq-find (lambda (new)
                                            (eq (org-truss--snapshot-telling-role new) role))
                                          news))))))
    (setq snapshot
          (plist-put snapshot :children
                     (append (mapcan (lambda (new)
                                       (or (seq-filter (lambda (old) (eq (funcall role-of old) new))
                                                       olds)
                                           (list new)))
                                     news)
                             (seq-remove role-of olds))))
    (org-truss--replace-subtree pos (org-truss--serialize snapshot (org-truss--level pos)))
    (org-truss-set-pattern pos 'telling pattern)))

(defun org-truss--snapshot-descendants (snapshot)
  "Return the snapshots below SNAPSHOT, depth first."
  (mapcan (lambda (c) (cons c (org-truss--snapshot-descendants c)))
          (plist-get snapshot :children)))

;;;; Links and properties

(defun org-truss--add-line (pos line)
  "Write LINE under the heading at POS, after its last line of text."
  (save-excursion
    (let* ((bounds (org-truss--text-bounds pos))
           (heading-end (progn (goto-char pos) (line-end-position))))
      (goto-char (cdr bounds))
      (skip-chars-backward " \t\n" heading-end)
      (insert "\n" line)
      (unless (looking-at "\n")
        (insert "\n")))))

(defun org-truss-add-include (pos id)
  "Include the member ID in the text of the heading at POS, after its last line.
In a list item of its own, - [[truss-include:ID]]; ID is the member's,
see `org-truss-ensure-id'."
  (org-truss--add-line pos (string-remove-suffix "\n" (org-truss--include-item id))))

(defun org-truss-remove-include (pos id)
  "Stop including the member ID in the text of the heading at POS.
The line that holds nothing but the include link goes; a link among other
words, alone."
  (let ((at (or (org-truss--include-line pos id) (org-truss--include-at pos id))))
    (when at
      (delete-region (car at) (cdr at))
      t)))

(defun org-truss--role-props (roles)
  "Return the properties that say ROLES, (KIND . ROLE) each, as an alist."
  (mapcar (lambda (r) (cons (org-truss-role-property (car r)) (symbol-name (cdr r)))) roles))

(defun org-truss--heading-term (pos)
  "Return (BEG END . TERM) for the term before :: in the heading at POS, or nil.
BEG and END bound the term and the :: after it."
  (org-with-point-at pos
    (let ((case-fold-search nil))
      (looking-at org-complex-heading-regexp))
    (let ((start (match-beginning 4)))
      (when start
        (goto-char start)
        (when (looking-at org-truss--heading-term-re)
          (cons (match-beginning 1) (cons (match-end 0) (match-string-no-properties 1))))))))

(defun org-truss--parent-pattern (pos kind)
  "Return the pattern of KIND of the heading above the heading at POS, or nil."
  (org-with-point-at pos
    (and (org-up-heading-safe) (org-truss-heading-pattern (point) kind))))

(defun org-truss-set-role (pos kind role)
  "Make the heading at POS play ROLE in the pattern of KIND above it.
With ROLE nil, it plays none there.  Before ::, as an item names it,
where no property names a role of KIND, its words name none of another
kind and the pattern above has ROLE; else in the property.  A role of
a pattern of one role is played unnamed, and named nowhere."
  (let* ((property (org-truss-role-property kind))
         (pattern (org-truss--parent-pattern pos kind))
         (one (and pattern (null (cdr (org-truss-pattern-roles pattern)))))
         (term (org-truss--heading-term pos))
         (named (and term (org-truss--intern (cddr term))))
         ;; The kind its term names a role of, in the patterns above.
         (named-kind (and named
                          (seq-find (lambda (k)
                                      (let ((p (org-truss--parent-pattern pos k)))
                                        (and p (assq named (org-truss-pattern-roles p)))))
                                    org-truss-pattern-kinds))))
    (cond ((or (org-entry-get pos property)
               ;; Before :: a role is read in the pattern above alone.
               (and role (not (assq role (org-truss-pattern-roles pattern)))))
           (if (and role (not one))
               (org-entry-put pos property (symbol-name role))
             (org-entry-delete pos property)))
          ((and named-kind (not (eq named-kind kind)))
           (when (and role (not one))
             (org-entry-put pos property (symbol-name role))))
          (t
           (save-excursion
             (when (eq named-kind kind)
               (delete-region (car term) (cadr term)))
             (when (and role (not one))
               (org-with-point-at pos
                 (let ((case-fold-search nil))
                   (looking-at org-complex-heading-regexp))
                 (goto-char (or (match-beginning 4) (line-end-position)))
                 (when (and (null (match-beginning 4)) (not (eq (char-before) ?\s)))
                   (insert " "))
                 (insert (symbol-name role) " :: "))))))))

(defun org-truss-set-item-role (pos role)
  "Make the item at POS play ROLE, its term before ::, or none with nil.
A term naming no role is its words, and stays."
  (save-excursion
    (goto-char pos)
    (when (looking-at org-list-full-item-re)
      (let ((term (match-string-no-properties 4))
            (roles (mapcar #'car (org-truss-pattern-roles-all))))
        (cond ((and term (memq (org-truss--intern term) roles))
               (goto-char (match-beginning 4))
               (looking-at "[^\n]*?[ \t]+::[ \t]*")
               (delete-region (point) (match-end 0)))
              (t (goto-char (match-end 0))
                 (skip-chars-backward " \t")
                 (skip-chars-forward " \t")))
        (when role
          (insert (symbol-name role) " :: "))))))

(defun org-truss--heading-attr-pos (pos)
  "Return where the #+attr_truss naming the heading at POS's patterns is.
Nil when there is none.
That of the first list of its members in its text, or else the first
line that marks no list; see `org-truss--heading-attrs'."
  (let* ((bounds (save-excursion (org-truss--text-bounds pos)))
         (lists (save-excursion (org-truss--text-item-lists (car bounds) (cdr bounds)))))
    (if lists
        (org-element-property :begin (car lists))
      (save-excursion
        (goto-char (car bounds))
        (let ((skip (org-truss--list-bounds
                     (save-restriction
                       (narrow-to-region (car bounds) (cdr bounds))
                       (seq-filter (lambda (e) (eq (org-element-type e) 'plain-list))
                                   (mapcan #'org-element-contents
                                           (seq-filter (lambda (e) (eq (org-element-type e) 'section))
                                                       (org-element-contents (org-element-parse-buffer))))))))
              found)
          (while (and (not found) (re-search-forward org-truss--attr-line-re (cdr bounds) t))
            (let ((at (line-beginning-position)))
              (unless (seq-some (lambda (r) (and (>= at (car r)) (< at (cdr r)))) skip)
                (setq found at))))
          found)))))

(defun org-truss--attr-plist-line (plist)
  "Return the #+attr_truss line saying PLIST: its patterns, :by and :as."
  (org-truss--attr-line
   (delq nil (mapcar (lambda (kind)
                       (let ((value (plist-get plist (intern (format ":%s" kind)))))
                         (and value (cons kind value))))
                     org-truss-pattern-kinds))
   (plist-get plist :as) (plist-get plist :by)))

(defun org-truss--set-heading-attr (pos key value)
  "Set KEY, :logic, :by and the like, to VALUE in the heading at POS's attr.
In its #+attr_truss; see `org-truss--heading-attr-pos'.  With VALUE nil,
take it off; a line that marks no list and is left saying nothing goes.
A heading with none is given one, VALUE given, at the end of its text,
before the headings under it."
  (let ((at (org-truss--heading-attr-pos pos)))
    (save-excursion
      (if at
          (let* ((plist (org-truss--attr-plist at))
                 (plist (if value (plist-put plist key value)
                          (org-plist-delete plist key)))
                 (line (org-truss--attr-plist-line plist)))
            (goto-char at)
            (let ((indent (current-indentation))
                  (marks (save-excursion (forward-line) (skip-chars-forward " \t") (org-at-item-p))))
              (if (and (not marks) (equal line "#+attr_truss:"))
                  (delete-region at (min (point-max) (1+ (line-end-position))))
                (delete-region at (line-end-position))
                (insert (make-string indent ?\s) line))))
        (when value
          (org-truss--add-line pos (org-truss--attr-plist-line (list key value))))))))

(defun org-truss-set-pattern (pos kind pattern)
  "Give the heading at POS PATTERN of KIND.
KIND is `logic', `breakdown' or `telling'; see `org-truss-patterns'.  With
PATTERN nil it has none of that kind: no reasons, no breakdown, or no
order asked of its supporting members.  Written in its #+attr_truss,
where it can be read; in its property where one names that kind."
  (let ((property (alist-get kind org-truss-pattern-properties)))
    (cond ((org-entry-get pos property)
           (if pattern
               (org-entry-put pos property (symbol-name pattern))
             (org-entry-delete pos property)))
          (t (org-truss--set-heading-attr pos (intern (format ":%s" kind)) pattern)))))

(defun org-truss--rank (pos kind role)
  "Return where ROLE comes among the roles of the pattern of KIND at POS."
  (or (seq-position (mapcar #'car (org-truss-pattern-roles (org-truss-heading-pattern pos kind)))
                    role)
      most-positive-fixnum))

(defun org-truss--one-role-p (pos kind)
  "Non-nil when the pattern of KIND of the heading at POS has one role.
That role is played without a term: a heading under it names none."
  (let ((roles (org-truss-pattern-roles (org-truss-heading-pattern pos kind))))
    (and roles (null (cdr roles)))))

(defun org-truss--heading-role (pos kind)
  "Return the role the heading at POS plays in the pattern of KIND above it.
Named in its property, or before :: in its words: a role of that pattern,
or one of no pattern above, left from one it had before.  Nil when
neither names one."
  (or (org-truss--intern (org-entry-get pos (org-truss-role-property kind)))
      (let* ((term (org-truss--heading-term pos))
             (named (and term (org-truss--intern (cddr term)))))
        (and named
             (assq named (org-truss-pattern-roles-all))
             (or (assq named (org-truss-pattern-roles (org-truss--parent-pattern pos kind)))
                 (not (seq-some (lambda (k)
                                  (assq named (org-truss-pattern-roles (org-truss--parent-pattern pos k))))
                                org-truss-pattern-kinds)))
             named))))

(defun org-truss-add-heading (parent words &optional props text)
  "Write a heading of WORDS, with PROPS and TEXT under it, under PARENT.
PARENT is the position of any heading.  The new one goes where the
patterns of PARENT list the roles its PROPS give it: before the first
heading there that plays, in one of those patterns, a role listed after
its own; or else last.  A role of a pattern of one role is not
written; see `org-truss--one-role-p'.  One role is named before ::, as
an item names it; another stays a property.  Return a marker at it."
  (let* ((kinds (seq-filter (lambda (kind) (assoc (org-truss-role-property kind) props))
                            org-truss-pattern-kinds))
         (rank (lambda (kind role) (org-truss--rank parent kind role)))
         (own (lambda (kind) (org-truss--intern (cdr (assoc (org-truss-role-property kind) props)))))
         (before (seq-find (lambda (child)
                             (seq-some (lambda (kind)
                                         (let ((theirs (org-truss--heading-role child kind)))
                                           (and theirs (> (funcall rank kind theirs)
                                                          (funcall rank kind (funcall own kind))))))
                                       kinds))
                           (org-truss--child-headings parent)))
         (written (seq-remove (lambda (prop)
                                (seq-some (lambda (kind)
                                            (and (equal (car prop) (org-truss-role-property kind))
                                                 (org-truss--one-role-p parent kind)))
                                          kinds))
                              props))
         (named (seq-find (lambda (prop)
                            (seq-some (lambda (kind) (equal (car prop) (org-truss-role-property kind)))
                                      kinds))
                          written))
         (words (if named
                    (let ((id (and (string-match "\\`<<[^<>\n]+>>" words) (match-string 0 words))))
                      (concat (cdr named) " :: " id (if id (substring words (length id)) words)))
                  words))
         (written (remq named written)))
    (save-excursion
      (if before
          (goto-char before)
        (goto-char parent)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n")))
      (let ((at (point-marker)))
        (insert (make-string (1+ (org-truss--level parent)) ?*) " " words "\n"
                (org-truss--drawer written) (or text "") "\n")
        at))))

(defun org-truss-add-role-member (pos kind role)
  "Put under the heading at POS a member for ROLE of its pattern of KIND.
Its words the role's in `org-truss-language' and playing it, it goes
where the pattern lists the role, as `org-truss-add-heading' puts it.
Return a marker at it."
  (org-truss-add-heading pos (org-truss-role-label role)
                         (org-truss--role-props (list (cons kind role)))))

(defun org-truss-add-role-members (pos gaps)
  "Put under the heading at POS a member for each role GAPS names.
GAPS are (KIND ROLE . SHORT-BY), as `org-truss-gaps' gives them: as many
members for a role as it is short by, each put in by
`org-truss-add-role-member'.  A pattern asks for members a writer cannot
be expected to make by hand; this makes them.  Return the number made."
  (let ((n 0))
    (pcase-dolist (`(,kind ,role . ,short) gaps)
      (dotimes (_ short)
        (setq n (1+ n))
        (set-marker (org-truss-add-role-member pos kind role) nil)))
    n))

(defun org-truss--goto-first-heading ()
  "Go to the first heading of the buffer, past the guide before it.
The guide's examples, <<m21>> among them, are no member's."
  (goto-char (point-min))
  (unless (org-at-heading-p)
    (outline-next-heading)))

(defconst org-truss--id-re
  "^[ \t]*:CUSTOM_ID:[ \t]+m\\([0-9]+\\)[ \t]*$\\|<<m\\([0-9]+\\)>>"
  "An ID of the form org-truss gives, m and a number: a heading's CUSTOM_ID,
or an item's <<m7>>.")

(defun org-truss--next-id ()
  "Return an ID no member in the buffer has: m and the next number."
  (org-with-wide-buffer
   (org-truss--goto-first-heading)
   (let ((case-fold-search t)
         (top 0))
     (while (re-search-forward org-truss--id-re nil t)
       (setq top (max top (string-to-number (or (match-string 1) (match-string 2))))))
     (format "m%d" (1+ top)))))

(defun org-truss-ensure-id (pos)
  "Return the ID of the member at POS, giving it one when it has none.
A new one is m and the next number free in the file, written <<m7>>
where its words start, a heading's as an item's, so it goes with them
when one is made the other; a heading's CUSTOM_ID, when it has one, is
its ID too.  Links point to a member by it, so its words can be
rewritten freely."
  (if (save-excursion (goto-char pos) (not (org-at-heading-p)))
      (org-truss--ensure-item-id pos)
    (org-truss--ensure-heading-id pos)))

(defun org-truss--ensure-item-id (pos)
  "Return the ID of the item at POS, giving it one when it has none."
  (save-excursion
    (goto-char pos)
    (let ((line-end (line-end-position)))
      (if (re-search-forward "<<\\([^<>\n]+\\)>>" line-end t)
          (match-string-no-properties 1)
        (let ((id (org-truss--next-id)))
          (goto-char pos)
          (looking-at org-list-full-item-re)
          ;; After the bullet, the box and the term, where the words start.
          (goto-char (match-end 0))
          (skip-chars-forward " \t" line-end)
          (insert "<<" id ">>")
          id)))))

(defun org-truss--ensure-heading-id (pos)
  "Return the ID of the heading at POS, giving it one when it has none.
<<m7>> in its words, or its CUSTOM_ID; a new one is written <<m7>>,
before its words."
  (let ((id (or (org-with-point-at pos (org-truss--heading-target))
                (let ((custom (org-entry-get pos "CUSTOM_ID")))
                  (and custom (not (string-blank-p custom)) (string-trim custom))))))
    (or id
        (let ((id (org-truss--next-id)))
          (org-with-point-at pos
            (let ((case-fold-search nil))
              (looking-at org-complex-heading-regexp))
            ;; After the stars, the keyword and the priority, where the
            ;; words start.
            (goto-char (or (match-beginning 4) (line-end-position)))
            (when (and (null (match-beginning 4)) (not (eq (char-before) ?\s)))
              (insert " "))
            (insert "<<" id ">>"))
          id))))

;;;; The pattern of a member written as an item

;; An item's patterns are named in #+attr_truss before the list of its
;; supporting members, inside it; the members a pattern asks for are
;; items of that list.

(defun org-truss--item-column (pos)
  "Return the column the text of the item at POS starts at."
  (save-excursion
    (goto-char pos)
    (looking-at "[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]+")
    (- (match-end 0) (match-beginning 0))))

(defun org-truss--item-end (pos)
  "Return where the item at POS ends, what is under it included."
  (save-excursion
    (goto-char pos)
    (let ((struct (org-list-struct)))
      (org-list-get-item-end pos struct))))

(defun org-truss--item-attr (pos)
  "Return where the #+attr_truss right in the item at POS is, or nil."
  (let ((column (org-truss--item-column pos))
        (end (org-truss--item-end pos)))
    (save-excursion
      (goto-char pos)
      (forward-line)
      (catch 'found
        (while (re-search-forward "^\\([ \t]*\\)#\\+attr_truss:" end t)
          (when (= (length (match-string 1)) column)
            (throw 'found (line-beginning-position))))
        nil))))

(defun org-truss--attr-plist (pos)
  "Return what the #+attr_truss line at POS says, as a plist."
  (save-excursion
    (goto-char pos)
    (looking-at "[ \t]*#\\+attr_truss:\\(.*\\)$")
    (condition-case nil (car (read-from-string (concat "(" (match-string 1) ")")))
      (error nil))))

(defun org-truss-set-item-pattern (pos kind pattern)
  "Give the item at POS PATTERN of KIND, in the #+attr_truss right in it.
With PATTERN nil it has none of that kind.  An item with no list of its
own is given the line, at its end, for the list to follow."
  (let* ((attr (org-truss--item-attr pos))
         (plist (and attr (org-truss--attr-plist attr)))
         (patterns (delq nil (mapcar (lambda (k)
                                       (let ((value (if (eq k kind)
                                                        pattern
                                                      (plist-get plist (intern (format ":%s" k))))))
                                         (and value (cons k value))))
                                     org-truss-pattern-kinds)))
         (line (concat (make-string (org-truss--item-column pos) ?\s)
                       (org-truss--attr-line patterns (plist-get plist :as) (plist-get plist :by)))))
    (save-excursion
      (if attr
          (progn (goto-char attr)
                 (delete-region attr (line-end-position))
                 (insert line))
        (when pattern
          (goto-char (org-truss--item-end pos))
          (skip-chars-backward " \t\n")
          (end-of-line)
          (insert "\n" line))))))

(defun org-truss-add-role-items (pos gaps)
  "Put in the list of the item at POS an item for each role GAPS names.
GAPS are (KIND ROLE . SHORT-BY), as `org-truss-gaps' gives them.  Each
is written after the items there, its words the role's in
`org-truss-language', its role before :: where its pattern has more than
one.  Return the number made."
  (let ((attr (org-truss--item-attr pos))
        (column (org-truss--item-column pos))
        (n 0))
    (when attr
      (let* ((plist (org-truss--attr-plist attr))
             (numbered nil)
             (count 0)
             (at (save-excursion
                   (goto-char attr)
                   (forward-line)
                   ;; Past the list's items and what is under them.
                   (let ((end (org-truss--item-end pos)))
                     (while (and (< (point) end)
                                 (or (looking-at "[ \t]*$")
                                     (>= (current-indentation) column)))
                       (when (and (= (current-indentation) column)
                                  (looking-at "[ \t]*\\(?:[-+]\\|\\([0-9]+\\)[.)]\\)[ \t]"))
                         (setq count (1+ count)
                               numbered (or numbered (match-beginning 1))))
                       (forward-line))
                     (skip-chars-backward " \t\n")
                     (if (bobp) (point) (progn (end-of-line) (point)))))))
        (pcase-dolist (`(,kind ,role . ,short) gaps)
          (let* ((pattern (org-truss--intern (format "%s" (plist-get plist (intern (format ":%s" kind))))))
                 (many (cdr (org-truss-pattern-roles pattern)))
                 (numbered (or numbered (eq (plist-get (org-truss-pattern pattern) :list) 'numbered))))
            (dotimes (_ short)
              (setq n (1+ n) count (1+ count))
              (save-excursion
                (goto-char at)
                (insert "\n" (make-string column ?\s)
                        (if numbered (format "%d. " count) "- ")
                        (if many (format "%s :: " role) "")
                        (org-truss-role-label role))
                (setq at (point))))))))
    n))

;;;; A heading made an item, an item a heading

;; Org's own C-c * and C-c - turn items into headings and back.  In a truss
;; file they carry what makes a member one: the role it plays, written
;; before :: on an item and in a _ROLE property on a heading; the patterns
;; of its truss, in #+attr_truss before its list or in properties; and
;; TRUSS_BY and TRUSS_AS.  Its ID, <<m7>>, goes with its words, and its tags with
;; org-item-tags.  Where Org would put a member under another -- an item
;; following the one made a heading, or a heading made an item in the
;; text of the heading before it -- nothing is done and it is said why.

(defun org-truss--toggle-range ()
  "Return (BEG . END) of the lines Org's C-c * or C-c - act on.
The region from its first non-blank line, or the current line."
  (if (org-region-active-p)
      (cons (save-excursion
              (goto-char (region-beginning))
              (skip-chars-forward " \r\t\n")
              (line-beginning-position))
            (save-excursion (goto-char (region-end)) (line-end-position)))
    (cons (line-beginning-position) (line-end-position))))

(defun org-truss--attr-line (patterns as &optional by)
  "Return the #+attr_truss line naming PATTERNS, (KIND . PATTERN), BY and AS.
BY, the axis, right after the breakdown it cuts."
  (string-trim-right
   (concat "#+attr_truss:"
           (mapconcat (lambda (p)
                        (concat (format " :%s %s" (car p) (cdr p))
                                (if (and by (eq (car p) 'breakdown)) (format " :by %s" by) "")))
                      patterns "")
           (if (and by (not (assq 'breakdown patterns))) (format " :by %s" by) "")
           (if as (format " :as %s" as) ""))))

(defun org-truss--member-shape (member)
  "Return what of MEMBER a conversion carries, as a plist.
:patterns (KIND . PATTERN), :by and :as, those of its truss."
  (list :patterns (delq nil (mapcar (lambda (kind)
                                      (let ((p (org-truss-member-pattern member kind)))
                                        (and p (cons kind p))))
                                    org-truss-pattern-kinds))
        :by (org-truss-member-by member)
        :as (org-truss-member-as member)))

(defun org-truss--one-role-of-p (member kind)
  "Non-nil when MEMBER's pattern of KIND has one role."
  (let ((p (org-truss-member-pattern member kind)))
    (and p (null (cdr (org-truss-pattern-roles p))))))

(defun org-truss--items-to-headings (fn args)
  "Make items headings by FN, Org's `org-toggle-heading' called with ARGS.
See `org-truss--toggle-heading'."
  (let* ((range (org-truss--toggle-range))
         (model (org-truss-read))
         (items nil))
    ;; The items made headings: those starting a line in the range.
    (save-excursion
      (goto-char (car range))
      (while (and (<= (point) (cdr range)) (not (eobp)))
        (when (org-at-item-p)
          (let ((m (org-truss-member-at model (point))))
            (when m (push m items))))
        (forward-line)))
    (setq items (nreverse items))
    ;; An item after them in its list would be made the text of the last.
    (dolist (m items)
      (let ((next (save-excursion
                    (goto-char (org-truss-member-pos m))
                    (let* ((struct (org-list-struct)))
                      (org-list-get-next-item (point) struct (org-list-prevs-alist struct))))))
        (when (and next (> next (cdr range)))
          (user-error "%s" (substitute-command-keys
                            "Org would put the items after it under it: make them headings too, \
selecting them all, or move it last")))))
    (let ((records
           (mapcar (lambda (m)
                     (let* ((up (org-truss-parent model m))
                            (roles (seq-remove (lambda (r) (org-truss--one-role-of-p up (car r)))
                                               (org-truss-member-roles m))))
                       (list :marker (copy-marker (org-truss-member-pos m))
                             :roles roles
                             :shape (org-truss--member-shape m)
                             :term (save-excursion
                                     (goto-char (org-truss-member-pos m))
                                     (and (looking-at org-list-full-item-re)
                                          (match-string-no-properties 4)
                                          (string-trim (match-string-no-properties 4)))))))
                   items)))
      (when (seq-some (lambda (r) (cdr (plist-get r :roles))) records)
        (user-error "An item names one role before ::; one plays two"))
      (apply fn args)
      ;; Org writes the region anew, which leaves every marker in it at
      ;; its start: the headings it made are the items, in order.
      (save-excursion
        (goto-char (car range))
        (forward-line 0)
        (dolist (r records)
          (when (or (org-at-heading-p) (re-search-forward org-heading-regexp nil t))
            (forward-line 0)
            (set-marker (plist-get r :marker) (point))
            (forward-line))))
      ;; What the item said stays where it was written: its role or value
      ;; before ::, which Org would take for its words, and #+attr_truss,
      ;; which a heading's text reads as an item's does.
      (dolist (r records)
        (org-with-point-at (plist-get r :marker)
          (when (org-at-heading-p)
            ;; One space after the stars, as Org writes a heading.
            (when (looking-at "\\(\\*+\\)[ \t][ \t]+")
              (replace-match "\\1 "))
            (forward-line 0)
            (let ((term (plist-get r :term)))
              (when (and term
                         (looking-at (concat "\\(\\*+ +\\(?:<<[^<>\n]+>>\\)?\\)"
                                             (regexp-quote term) "\\(?:[ \t]+::\\)?[ \t]*")))
                (replace-match (concat (match-string 1) term " ::"
                                       (if (= (match-end 0) (line-end-position)) "" " "))
                               t t)))
            ;; Org drops the #+attr_truss of a list it makes headings.
            (let ((shape (plist-get r :shape))
                  (pos (point)))
              (pcase-dolist (`(,kind . ,pattern) (plist-get shape :patterns))
                (unless (org-truss-heading-pattern pos kind)
                  (org-truss-set-pattern pos kind pattern)))
              (dolist (key '(:by :as))
                (let ((value (plist-get shape key)))
                  (when (and value
                             (not (seq-some (lambda (a) (plist-get a key)) (org-truss--heading-attrs pos))))
                    (org-truss--set-heading-attr pos key value))))))))
      (dolist (r records)
        (set-marker (plist-get r :marker) nil)))))

(defun org-truss--headings-to-items (fn args)
  "Make headings items by FN, Org's `org-toggle-item' called with ARGS.
See `org-truss--toggle-item'."
  (let* ((range (org-truss--toggle-range))
         (model (org-truss-read))
         (headings nil))
    (save-excursion
      (goto-char (car range))
      (while (and (<= (point) (cdr range)) (not (eobp)))
        (when (org-at-heading-p)
          (let ((m (org-truss-member-at model (point))))
            (when m (push m headings))))
        (forward-line)))
    (setq headings (nreverse headings))
    (when headings
      ;; Org writes an item in the text of the heading before it: the
      ;; first one made an item is to be the first heading under its member.
      (let ((first (car headings)))
        (when (save-excursion (goto-char (org-truss-member-pos first))
                              (org-get-previous-sibling))
          (user-error "Org would put it in the text of the heading before it: \
make items from the first heading under %s on"
                      (org-truss-member-words (org-truss-parent model first)))))
      (let* ((records
              (mapcar (lambda (m)
                        (let* ((up (org-truss-parent model m))
                               (roles (seq-remove (lambda (r) (org-truss--one-role-of-p up (car r)))
                                                  (org-truss-member-roles m))))
                          (when (cdr roles)
                            (user-error "%s plays two roles; an item names one before ::"
                                        (org-truss-member-words m)))
                          ;; One named before :: in its words is there already.
                          (setq roles (seq-filter (lambda (r)
                                                    (org-entry-get (org-truss-member-pos m)
                                                                   (org-truss-role-property (car r))))
                                                  roles))
                          (list :marker (copy-marker (org-truss-member-pos m))
                                :id (and (org-entry-get (org-truss-member-pos m) "CUSTOM_ID")
                                         (org-truss-member-id m))
                                :role (cdar roles)
                                :shape (org-truss--member-shape m))))
                      headings))
             (top (copy-marker (org-truss-member-pos (car headings)))))
        (apply fn args)
        (dolist (r records)
          (org-with-point-at (plist-get r :marker)
            (when (org-at-item-p)
              (looking-at org-list-full-item-re)
              (goto-char (match-end 0))
              (skip-chars-forward " \t" (line-end-position))
              (when (and (plist-get r :id)
                         (not (save-excursion (re-search-forward "<<[^<>\n]+>>" (line-end-position) t))))
                (insert "<<" (plist-get r :id) ">>")
                (goto-char (match-end 0))
                (forward-line 0)
                (looking-at org-list-full-item-re)
                (goto-char (match-end 0))
                (skip-chars-forward " \t" (line-end-position)))
              (when (plist-get r :role)
                (insert (symbol-name (plist-get r :role)) " :: "))
              (org-truss--mark-list-under (plist-get r :shape)))))
        ;; The list the first is in, now its member's.
        (org-with-point-at top
          (when (org-at-item-p)
            (let ((list (org-element-lineage (org-element-at-point) '(plain-list) t)))
              (unless (and list (org-element-property :attr_truss list))
                (goto-char (org-element-property :begin list))
                (insert (make-string (current-indentation) ?\s) "#+attr_truss:\n")))))
        (set-marker top nil)
        (dolist (r records) (set-marker (plist-get r :marker) nil))))))

(defun org-truss--mark-list-under (shape)
  "Name SHAPE's patterns, :by and :as before the first list in the item at point.
SHAPE is what `org-truss--member-shape' gives.  The list made of the
headings that were under it, or a marked list in its text naming none."
  (let ((patterns (plist-get shape :patterns))
        (as (plist-get shape :as))
        (by (plist-get shape :by))
        (item (org-element-lineage (org-element-at-point) '(item) t)))
    (when (and item (or patterns as by) (org-element-property :contents-end item))
      (save-excursion
        (goto-char (org-element-property :contents-begin item))
        (when (re-search-forward "^\\([ \t]*\\)\\(#\\+attr_truss:.*\n[ \t]*\\)?\\(?:[-+]\\|[0-9]+[.)]\\)[ \t]"
                                 (org-element-property :contents-end item) t)
          (let ((indent (match-string 1))
                (marked (match-string 2)))
            (goto-char (match-beginning 0))
            (cond ((null marked)
                   (insert indent (org-truss--attr-line patterns as by) "\n"))
                  ((string-match-p "\\`#\\+attr_truss:[ \t]*\n" (string-trim-left marked))
                   (delete-region (point) (line-end-position))
                   (insert indent (org-truss--attr-line patterns as by))))))))))

(defun org-truss--toggle-heading (fn &rest args)
  "Around `org-toggle-heading': in a truss file, items made headings keep
their roles and patterns.  FN is the command, ARGS its arguments."
  (if (and (org-truss-file-p)
           (null (car args))
           (save-excursion (goto-char (car (org-truss--toggle-range))) (org-at-item-p)))
      (org-truss--items-to-headings fn args)
    (apply fn args)))

(defun org-truss--toggle-item (fn &rest args)
  "Around `org-toggle-item': in a truss file, headings made items keep
their roles, IDs and patterns.  FN is the command, ARGS its arguments."
  (if (and (org-truss-file-p)
           (null (car args))
           (save-excursion (goto-char (car (org-truss--toggle-range))) (org-at-heading-p)))
      (org-truss--headings-to-items fn args)
    (apply fn args)))

(advice-add 'org-toggle-heading :around #'org-truss--toggle-heading)
(advice-add 'org-toggle-item :around #'org-truss--toggle-item)

(provide 'org-truss-edit)

;;; org-truss-edit.el ends here

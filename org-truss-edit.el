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
  "Return the role SNAPSHOT's TRUSS_TELLING_ROLE names, or nil."
  (org-truss--intern (cdr (assoc (org-truss-role-property 'telling) (plist-get snapshot :props)))))

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
  "Return a snapshot of a new heading playing ROLE, a (ROLE . FLAGS), of a telling."
  (list :heading (org-truss-role-label (car role))
        :props (list (cons (org-truss-role-property 'telling) (symbol-name (car role))))
        :drawers "" :all "" :include-lines nil :children nil))

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
    (setq snapshot (plist-put snapshot :props
                              (org-truss--set-prop (plist-get snapshot :props)
                                                   "TRUSS_TELLING" (symbol-name pattern))))
    (org-truss--replace-subtree pos (org-truss--serialize snapshot (org-truss--level pos)))))

(defun org-truss--snapshot-descendants (snapshot)
  "Return the snapshots below SNAPSHOT, depth first."
  (mapcan (lambda (c) (cons c (org-truss--snapshot-descendants c)))
          (plist-get snapshot :children)))

(defun org-truss--snapshot-has-writing-p (snapshot)
  "Non-nil when SNAPSHOT holds text, besides the lines of its include links."
  (not (string-blank-p (plist-get snapshot :all))))

(defun org-truss-unwrap (pos &optional force)
  "Take away the headings under the member at POS, keeping their include links.
Every include link below moves up onto the member, in order.  Its
patterns go too, of every kind: what they asked for was asked of the
headings below, and there are none left to fill it.  When a heading
below has text of its own, which would be lost, nothing happens unless
FORCE, and the words of those headings are returned instead."
  (let* ((snapshot (org-truss--snapshot pos))
         (below (org-truss--snapshot-descendants snapshot))
         (lost (seq-filter #'org-truss--snapshot-has-writing-p below)))
    (if (and lost (not force))
        (mapcar (lambda (s) (plist-get s :heading)) lost)
      (setq snapshot (plist-put snapshot :include-lines
                                (seq-uniq (append (plist-get snapshot :include-lines)
                                                  (mapcan (lambda (s) (copy-sequence (plist-get s :include-lines)))
                                                          below)))))
      (setq snapshot (plist-put snapshot :children nil))
      (dolist (property (mapcar #'cdr org-truss-pattern-properties))
        (setq snapshot (plist-put snapshot :props
                                  (org-truss--set-prop (plist-get snapshot :props) property nil))))
      (org-truss--replace-subtree pos (org-truss--serialize snapshot (org-truss--level pos)))
      nil)))

(defun org-truss-dissolve (pos parent &optional force)
  "Remove the member at POS, moving every include link in it onto PARENT.
PARENT is the position of the member above.  Like `org-truss-unwrap', when
text would be lost nothing happens unless FORCE, and the words of the
headings holding it are returned."
  (let* ((snapshot (org-truss--snapshot pos))
         (all (cons snapshot (org-truss--snapshot-descendants snapshot)))
         (lost (seq-filter #'org-truss--snapshot-has-writing-p all)))
    (if (and lost (not force))
        (mapcar (lambda (s) (plist-get s :heading)) lost)
      (let ((ids (mapcan (lambda (s) (copy-sequence (plist-get s :include-lines))) all))
            (parent (copy-marker parent)))
        (save-excursion
          (goto-char pos)
          (delete-region pos (progn (org-end-of-subtree t t) (point))))
        (dolist (id ids)
          (org-truss-add-include parent id))
        (set-marker parent nil)
        nil))))

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

(defun org-truss-replace-include (pos old new)
  "Make the include link of OLD in the text at POS include NEW, where it stands.
Return non-nil when there was such a link."
  (let ((at (org-truss--include-at pos old))
        (case-fold-search nil))
    (when at
      (save-excursion
        (goto-char (car at))
        (re-search-forward (concat (regexp-quote org-truss-include-type) ":" (regexp-quote old) "\\]")
                           (cdr at))
        (replace-match (concat org-truss-include-type ":" new "]") t t))
      t)))

(defun org-truss-move-include (from id to)
  "Move the include link of ID from the heading at FROM to the one at TO."
  (let ((to (copy-marker to)))
    (when (org-truss-remove-include from id)
      (org-truss-add-include to id))
    (set-marker to nil)))

(defun org-truss-shift-include (pos id delta)
  "Move the line including ID in the text at POS by DELTA such lines.
DELTA is -1 or 1."
  (let* ((lines (plist-get (org-truss--text-at pos) :include-lines))
         (i (seq-position lines id))
         (j (and i (+ i delta))))
    (when (and j (<= 0 j) (< j (length lines)))
      (let ((a (org-truss--include-line pos (nth (min i j) lines)))
            (b (org-truss--include-line pos (nth (max i j) lines))))
        (save-excursion
          (let ((text-a (buffer-substring (car a) (cdr a)))
                (text-b (buffer-substring (car b) (cdr b))))
            (goto-char (car b))
            (delete-region (car b) (cdr b))
            (insert text-a)
            (goto-char (car a))
            (delete-region (car a) (cdr a))
            (insert text-b))))
      t)))

(defun org-truss--role-props (roles)
  "Return the properties that say ROLES, (KIND . ROLE) each, as an alist."
  (mapcar (lambda (r) (cons (org-truss-role-property (car r)) (symbol-name (cdr r)))) roles))

(defun org-truss-set-role (pos kind role)
  "Make the heading at POS play ROLE in the pattern of KIND above it.
With ROLE nil, it plays none there."
  (if role
      (org-entry-put pos (org-truss-role-property kind) (symbol-name role))
    (org-entry-delete pos (org-truss-role-property kind))))

(defun org-truss-set-pattern (pos kind pattern)
  "Give the heading at POS PATTERN of KIND.
KIND is `logic', `breakdown' or `telling'; see `org-truss-patterns'.  With
PATTERN nil it has none of that kind: no reasons, no breakdown, or no
order asked of its supporting members."
  (let ((property (alist-get kind org-truss-pattern-properties)))
    (if pattern
        (org-entry-put pos property (symbol-name pattern))
      (org-entry-delete pos property))))

(defun org-truss--rank (pos kind role)
  "Return where ROLE comes among the roles of the pattern of KIND at POS."
  (or (seq-position (mapcar #'car (org-truss-pattern-roles
                                   (org-truss--intern (org-entry-get pos (alist-get kind org-truss-pattern-properties)))))
                    role)
      most-positive-fixnum))

(defun org-truss--one-role-p (pos kind)
  "Non-nil when the pattern of KIND of the heading at POS has one role.
That role is played without a term: a heading under it names none."
  (let ((roles (org-truss-pattern-roles
                (org-truss--intern (org-entry-get pos (alist-get kind org-truss-pattern-properties))))))
    (and roles (null (cdr roles)))))

(defun org-truss-add-heading (parent words &optional props text)
  "Write a heading of WORDS, with PROPS and TEXT under it, under PARENT.
PARENT is the position of any heading.  The new one goes where the
patterns of PARENT list the roles its PROPS give it: before the first
heading there that plays, in one of those patterns, a role listed after
its own; or else last.  A role of a pattern of one role is not
written; see `org-truss--one-role-p'.  Return a marker at it."
  (let* ((kinds (seq-filter (lambda (kind) (assoc (org-truss-role-property kind) props))
                            org-truss-pattern-kinds))
         (rank (lambda (kind role) (org-truss--rank parent kind role)))
         (own (lambda (kind) (org-truss--intern (cdr (assoc (org-truss-role-property kind) props)))))
         (before (seq-find (lambda (child)
                             (seq-some (lambda (kind)
                                         (let ((theirs (org-truss--intern
                                                        (org-entry-get child (org-truss-role-property kind)))))
                                           (and theirs (> (funcall rank kind theirs)
                                                          (funcall rank kind (funcall own kind))))))
                                       kinds))
                           (org-truss--child-headings parent)))
         (written (seq-remove (lambda (prop)
                                (seq-some (lambda (kind)
                                            (and (equal (car prop) (org-truss-role-property kind))
                                                 (org-truss--one-role-p parent kind)))
                                          kinds))
                              props)))
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

(defun org-truss-add-member (parent words &optional roles)
  "Write a member of WORDS under the heading at PARENT, playing ROLES.
ROLES are (KIND . ROLE), the roles it plays in the patterns of PARENT; it
goes where they list them, as `org-truss-add-heading' puts it, or else
last.  Return a marker at the new heading."
  (org-truss-add-heading parent words (org-truss--role-props roles)))

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

(defun org-truss-add-ground (pos id)
  "Make the member ID a ground of the heading at POS.
A pointing link to it, # [[ID]], on a comment line of its own after the
heading's last line of text, where the reader does not see it; see
`org-truss-ensure-id'."
  (org-truss--add-line pos (format "# [[%s]]" (org-truss--pointing-target id))))

(defun org-truss--goto-first-heading ()
  "Go to the first heading of the buffer, past the guide before it.
The guide's examples, <<m21>> among them, are no member's."
  (goto-char (point-min))
  (unless (org-at-heading-p)
    (outline-next-heading)))

(defun org-truss--pointing-line (pos id)
  "Return (BEG . END) of the line pointing to ID in the text at POS, or nil.
A line holding nothing but the pointing link, [[#ID]] or [[ID]], as a
list item or not, as a comment or not."
  (let* ((bounds (org-truss--text-bounds pos))
         (re (format "^[ \t]*\\(?:#[ \t]+\\)?\\(?:[-+] \\|[0-9]+[.)] \\)?\\[\\[#?%s\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*$"
                     (regexp-quote id))))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward re (cdr bounds) t)
        (cons (line-beginning-position)
              (min (point-max) (1+ (line-end-position))))))))

(defun org-truss-remove-ground (pos id)
  "Stop the heading at POS standing on the member ID.
The line that holds nothing but the pointing link to it goes.  A link
among other words is left, for the words to be rewritten; nil is
returned then."
  (let ((at (org-truss--pointing-line pos id)))
    (when at
      (delete-region (car at) (cdr at))
      t)))

(defun org-truss-toggle-assumption (pos)
  "Tag the member at POS :assumption:, or take the tag off.  Return non-nil if on.
A heading's tags, or those at the end of an item's first line."
  (org-with-point-at pos
    (org-item-tags-toggle org-truss-assumption-tag)))

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

(defun org-truss-lead-line (pos)
  "Return where a lead is written in the text of the heading at POS, or nil.
Before the first line holding an include link alone, on an empty line
written for it: what is written there opens what the member includes.
Nil when no line holds one."
  (save-excursion
    (let ((bounds (org-truss--text-bounds pos)))
      (goto-char (car bounds))
      (when (re-search-forward org-truss--include-line-re (cdr bounds) t)
        (goto-char (line-beginning-position))
        (insert "\n")
        (1- (point))))))

;;;; A heading made an item, an item a heading

;; Org's own C-c * and C-c - turn items into headings and back.  In a truss
;; file they carry what makes a member one: the role it plays, written
;; before :: on an item and in a _ROLE property on a heading; the patterns
;; of its truss, in #+attr_truss before its list or in properties; and
;; TRUSS_AS.  Its ID, <<m7>>, goes with its words, and its tags with
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

(defun org-truss--attr-line (patterns as)
  "Return the #+attr_truss line naming PATTERNS, (KIND . PATTERN), and AS."
  (string-trim-right
   (concat "#+attr_truss:"
           (mapconcat (lambda (p) (format " :%s %s" (car p) (cdr p))) patterns "")
           (if as (format " :as %s" as) ""))))

(defun org-truss--member-shape (member)
  "Return what of MEMBER a conversion carries, as a plist.
:patterns (KIND . PATTERN) and :as, those of its truss."
  (list :patterns (delq nil (mapcar (lambda (kind)
                                      (let ((p (org-truss-member-pattern member kind)))
                                        (and p (cons kind p))))
                                    org-truss-pattern-kinds))
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
                             :holder (copy-marker (org-truss-member-holder m))
                             :up-shape (and up (org-truss--member-shape up)))))
                   items)))
      (when (seq-some (lambda (r) (cdr (plist-get r :roles))) records)
        (user-error "An item names one role before ::; one plays two"))
      ;; The term before :: is its role, not its words: Org would keep it
      ;; as words.
      (dolist (r records)
        (when (plist-get r :roles)
          (save-excursion
            (goto-char (plist-get r :marker))
            (when (looking-at "\\([ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t]+\\(?:\\[[ X-]\\][ \t]+\\)?\\)[^\n]*?[ \t]+::[ \t]*")
              (replace-match "\\1")))))
      (apply fn args)
      (dolist (r records)
        (org-with-point-at (plist-get r :marker)
          (when (org-at-heading-p)
            ;; One space after the stars, as Org writes a heading.
            (when (looking-at "\\(\\*+\\)[ \t][ \t]+")
              (replace-match "\\1 "))
            (pcase-dolist (`(,kind . ,role) (plist-get r :roles))
              (org-entry-put nil (org-truss-role-property kind) (symbol-name role)))
            ;; Its patterns, when no list of its own is left to name them.
            (unless (org-truss--text-item-lists (point) (cdr (org-truss--text-bounds (point))))
              (let ((shape (plist-get r :shape)))
                (pcase-dolist (`(,kind . ,pattern) (plist-get shape :patterns))
                  (org-entry-put nil (alist-get kind org-truss-pattern-properties) (symbol-name pattern)))
                (when (plist-get shape :as)
                  (org-entry-put nil "TRUSS_AS" (symbol-name (plist-get shape :as)))))))))
      ;; A #+attr_truss left with no list after it gives its patterns to
      ;; the heading whose text it is in.
      (dolist (holder (seq-uniq (mapcar (lambda (r) (marker-position (plist-get r :holder))) records)))
        (org-truss--dangling-attrs holder))
      (dolist (r records)
        (set-marker (plist-get r :marker) nil)
        (set-marker (plist-get r :holder) nil)))))

(defun org-truss--dangling-attrs (pos)
  "Give the heading at POS the patterns of a #+attr_truss in its text that
marks no list, and take the line away."
  (setq pos (copy-marker pos))
  (save-excursion
    (let ((bounds (org-truss--text-bounds pos)))
      (goto-char (car bounds))
      (while (re-search-forward "^[ \t]*#\\+attr_truss:\\(.*\\)$" (cdr bounds) t)
        (let ((line (match-string 1))
              (beg (copy-marker (line-beginning-position))))
          (unless (save-excursion
                    (forward-line)
                    (skip-chars-forward " \t\n")
                    (org-at-item-p))
            (let ((plist (condition-case nil (car (read-from-string (concat "(" line ")")))
                           (error nil))))
              (org-with-point-at pos
                (dolist (kind org-truss-pattern-kinds)
                  (let ((value (plist-get plist (intern (format ":%s" kind))))
                        (property (alist-get kind org-truss-pattern-properties)))
                    (when (and value (not (org-entry-get nil property)))
                      (org-entry-put nil property (format "%s" value)))))
                (let ((as (plist-get plist :as)))
                  (when (and as (not (org-entry-get nil "TRUSS_AS")))
                    (org-entry-put nil "TRUSS_AS" (format "%s" as))))))
            (goto-char beg)
            (delete-region beg (min (point-max) (1+ (line-end-position))))
            (setq bounds (org-truss--text-bounds pos)))
          (set-marker beg nil))))))

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
  "Name SHAPE's patterns and :as before the first list in the item at point.
SHAPE is what `org-truss--member-shape' gives.  The list made of the
headings that were under it, or a marked list in its text naming none."
  (let ((patterns (plist-get shape :patterns))
        (as (plist-get shape :as))
        (item (org-element-lineage (org-element-at-point) '(item) t)))
    (when (and item (or patterns as) (org-element-property :contents-end item))
      (save-excursion
        (goto-char (org-element-property :contents-begin item))
        (when (re-search-forward "^\\([ \t]*\\)\\(#\\+attr_truss:.*\n[ \t]*\\)?\\(?:[-+]\\|[0-9]+[.)]\\)[ \t]"
                                 (org-element-property :contents-end item) t)
          (let ((indent (match-string 1))
                (marked (match-string 2)))
            (goto-char (match-beginning 0))
            (cond ((null marked)
                   (insert indent (org-truss--attr-line patterns as) "\n"))
                  ((string-match-p "\\`#\\+attr_truss:[ \t]*\n" (string-trim-left marked))
                   (delete-region (point) (line-end-position))
                   (insert indent (org-truss--attr-line patterns as))))))))))

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

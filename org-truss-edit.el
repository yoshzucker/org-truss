;;; org-truss-edit.el --- The edits made to a truss file  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The edits org-truss makes to a truss file, each at a position in its
;; buffer: sections rearranged, links, roles and grounds written, members
;; added, moved and deleted.  The board's commands make them.  What is read
;; from the file is in org-truss-core.el.

;;; Code:

(require 'org-truss-core)

;;;; What a section looks like on the page

;; Edits that rearrange sections read the subtree into a snapshot, change the
;; snapshot, and write the subtree back.  A snapshot keeps what it does not
;; understand -- notes, other drawers, the public block -- as written.

(defun org-truss--snapshot (pos)
  "Return a snapshot of the subtree at POS.
A plist of :heading (the text after the stars), :props, :drawers, :notes,
:public-raw, :links (the lines that tell members, of their own) and
:children."
  (let ((own (org-truss--own pos)))
    (save-excursion
      (goto-char pos)
      (looking-at "\\*+[ \t]+\\(.*\\)$")
      (list :heading (match-string-no-properties 1)
            :props (plist-get own :props)
            :drawers (plist-get own :drawers)
            :notes (plist-get own :notes)
            :public-raw (plist-get own :public-raw)
            :links (plist-get own :items)
            :children (mapcar #'org-truss--snapshot (org-truss--children pos))))))

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
          (org-truss--trim-blank-lines (plist-get snapshot :notes))
          (plist-get snapshot :public-raw)
          (mapconcat #'org-truss--link-item (plist-get snapshot :links) "")
          "\n"
          (mapconcat (lambda (c) (org-truss--serialize c (1+ level)))
                     (plist-get snapshot :children) "")))

(defun org-truss--link-item (ref)
  "Return the list item that tells the member REF where it is written."
  (format "- %s\n" (org-truss--include-link ref)))

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

(defun org-truss--place-snapshot (place)
  "Return a snapshot of a new, empty section for PLACE of a telling pattern."
  (list :heading (org-truss-role-label (car place))
        :props (list (cons (org-truss-role-property 'telling) (symbol-name (car place))))
        :drawers "" :notes "" :public-raw "" :links nil :children nil))

(defun org-truss-apply-section-telling (pos pattern)
  "Give the section at POS the telling PATTERN, and a section for each place.
A section already there whose TRUSS_TELLING_ROLE is one of the pattern's
places takes that place as it is -- heading, roles and all it holds -- so
nothing written is changed; a section for the place, named in
`org-truss-language', is added only where none does.  A section in none of
the places is kept after the rest -- outside the pattern, to be moved by
hand.  Links on the section itself stay on it."
  (let* ((news (mapcar #'org-truss--place-snapshot (org-truss-pattern-roles pattern)))
         (snapshot (org-truss--snapshot pos))
         (olds (plist-get snapshot :children))
         (place-of (lambda (old)
                     (let ((role (org-truss--snapshot-telling-role old)))
                       (and role (seq-find (lambda (new)
                                             (eq (org-truss--snapshot-telling-role new) role))
                                           news))))))
    (setq snapshot
          (plist-put snapshot :children
                     (append (mapcan (lambda (new)
                                       (or (seq-filter (lambda (old) (eq (funcall place-of old) new))
                                                       olds)
                                           (list new)))
                                     news)
                             (seq-remove place-of olds))))
    (setq snapshot (plist-put snapshot :props
                              (org-truss--set-prop (plist-get snapshot :props)
                                                   "TRUSS_TELLING" (symbol-name pattern))))
    (org-truss--replace-subtree pos (org-truss--serialize snapshot (org-truss--level pos)))))

(defun org-truss--snapshot-descendants (snapshot)
  "Return the snapshots below SNAPSHOT, depth first."
  (mapcan (lambda (c) (cons c (org-truss--snapshot-descendants c)))
          (plist-get snapshot :children)))

(defun org-truss--snapshot-has-writing-p (snapshot)
  "Non-nil when SNAPSHOT holds a public block or notes."
  (or (not (string-empty-p (plist-get snapshot :public-raw)))
      (not (string-blank-p (plist-get snapshot :notes)))))

(defun org-truss-unwrap (pos &optional force)
  "Take the sections below the section at POS away, keeping their links.
Every link below moves up onto the section, in order.  Its patterns go
too, of every kind: what they asked for was asked of the sections below,
and there are none left to fill it.  When a section below has a title or
notes of its own, which would be lost, nothing happens unless FORCE, and
the labels of those sections are returned instead."
  (let* ((snapshot (org-truss--snapshot pos))
         (below (org-truss--snapshot-descendants snapshot))
         (lost (seq-filter #'org-truss--snapshot-has-writing-p below)))
    (if (and lost (not force))
        (mapcar (lambda (s) (plist-get s :heading)) lost)
      (setq snapshot (plist-put snapshot :links
                                (seq-uniq (append (plist-get snapshot :links)
                                                  (mapcan (lambda (s) (copy-sequence (plist-get s :links)))
                                                          below)))))
      (setq snapshot (plist-put snapshot :children nil))
      (dolist (property (mapcar #'cdr org-truss-pattern-properties))
        (setq snapshot (plist-put snapshot :props
                                  (org-truss--set-prop (plist-get snapshot :props) property nil))))
      (org-truss--replace-subtree pos (org-truss--serialize snapshot (org-truss--level pos)))
      nil)))

(defun org-truss-dissolve (pos parent &optional force)
  "Remove the section at POS, moving every link in it onto PARENT.
PARENT is the position of the section above.  Like `org-truss-unwrap', when
writing would be lost nothing happens unless FORCE, and the labels of the
sections holding it are returned."
  (let* ((snapshot (org-truss--snapshot pos))
         (all (cons snapshot (org-truss--snapshot-descendants snapshot)))
         (lost (seq-filter #'org-truss--snapshot-has-writing-p all)))
    (if (and lost (not force))
        (mapcar (lambda (s) (plist-get s :heading)) lost)
      (let ((links (mapcan (lambda (s) (copy-sequence (plist-get s :links))) all))
            (parent (copy-marker parent)))
        (save-excursion
          (goto-char pos)
          (delete-region pos (progn (org-end-of-subtree t t) (point))))
        (dolist (ref links)
          (org-truss-add-link parent ref))
        (set-marker parent nil)
        nil))))

;;;; Links and properties

(defun org-truss-add-link (pos ref)
  "Tell the member REF under the heading at POS, after its last line of text.
In a list item of its own, - [[truss-include:REF]]; REF is the member's
CUSTOM_ID, see `org-truss-ensure-id'."
  (save-excursion
    (let* ((bounds (org-truss--own-bounds pos))
           (heading-end (progn (goto-char pos) (line-end-position))))
      (goto-char (cdr bounds))
      (skip-chars-backward " \t\n" heading-end)
      (insert "\n" (string-remove-suffix "\n" (org-truss--link-item ref)))
      (unless (looking-at "\n")
        (insert "\n")))))

(defun org-truss-remove-link (pos ref)
  "Stop telling the member REF under the heading at POS.
The line that holds nothing but the link goes; a link among other words,
alone."
  (let ((at (or (org-truss--link-line pos ref) (org-truss--include-at pos ref))))
    (when at
      (delete-region (car at) (cdr at))
      t)))

(defun org-truss-replace-link (pos old new)
  "Make the link telling OLD under the heading at POS tell NEW, where it stands.
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

(defun org-truss-move-link (from ref to)
  "Move the link telling the member REF from the heading at FROM to the one at TO."
  (let ((to (copy-marker to)))
    (when (org-truss-remove-link from ref)
      (org-truss-add-link to ref))
    (set-marker to nil)))

(defun org-truss-shift-link (pos ref delta)
  "Move the line telling REF under the heading at POS by DELTA such lines.
DELTA is -1 or 1."
  (let* ((items (plist-get (org-truss--own pos) :items))
         (i (seq-position items ref))
         (j (and i (+ i delta))))
    (when (and j (<= 0 j) (< j (length items)))
      (let ((a (org-truss--link-line pos (nth (min i j) items)))
            (b (org-truss--link-line pos (nth (max i j) items))))
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

(defun org-truss-add-section (parent name roles)
  "Add a section called NAME, playing ROLES, as the last one under PARENT.
ROLES are (KIND . ROLE), the roles it plays in the patterns of PARENT."
  (save-excursion
    (let ((level (1+ (org-truss--level parent))))
      (goto-char parent)
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n"))
      (insert (org-truss--serialize
               (list :heading name
                     :props (org-truss--role-props roles)
                     :drawers "" :notes "" :public-raw "" :links nil :children nil)
               level)))))

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
order asked of what is under it."
  (let ((property (alist-get kind org-truss-pattern-properties)))
    (if pattern
        (org-entry-put pos property (symbol-name pattern))
      (org-entry-delete pos property))))

(defvar org-truss-place-text-function nil
  "Function returning what a heading put in for a role says under its drawer.
Called with the position of the heading it goes under and the role; nil,
or the text.  The guidance sets it to give a role of a part its guide.")

(defun org-truss--rank (pos kind role)
  "Return where ROLE comes among the roles of the pattern of KIND at POS."
  (or (seq-position (mapcar #'car (org-truss-pattern-roles
                                   (org-truss--intern (org-entry-get pos (alist-get kind org-truss-pattern-properties)))))
                    role)
      most-positive-fixnum))

(defun org-truss-add-place (pos kind role)
  "Put under the heading at POS a heading for ROLE of its pattern of KIND.
Named for the role in `org-truss-language' and playing it, it goes where
the pattern lists the role: before the first heading there that plays a
role the pattern lists after it, or else last.  Return a marker at it."
  (let* ((rank (org-truss--rank pos kind role))
         (before (seq-find (lambda (child)
                             (let ((theirs (org-truss--intern (org-entry-get child (org-truss-role-property kind)))))
                               (and theirs (> (org-truss--rank pos kind theirs) rank))))
                           (org-truss--children pos)))
         (text (concat (make-string (1+ (org-truss--level pos)) ?*) " " (org-truss-role-label role) "\n"
                       (org-truss--drawer (org-truss--role-props (list (cons kind role))))
                       (or (and org-truss-place-text-function
                                (funcall org-truss-place-text-function pos role))
                           "")
                       "\n")))
    (save-excursion
      (if before
          (goto-char before)
        (goto-char pos)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n")))
      (let ((at (point-marker)))
        (insert text)
        at))))

(defun org-truss-add-places (pos gaps)
  "Put under the heading at POS a heading for each role GAPS names.
GAPS are (KIND ROLE . SHORT-BY), as `org-truss-gaps' gives them: as many
headings for a role as it is short by, each put in by
`org-truss-add-place'.  A pattern asks for headings a writer cannot be
expected to make by hand; this makes them.  Return the number made."
  (let ((n 0))
    (pcase-dolist (`(,kind ,role . ,short) gaps)
      (dotimes (_ short)
        (setq n (1+ n))
        (set-marker (org-truss-add-place pos kind role) nil)))
    n))

(defun org-truss--write-member-after (pos level label props)
  "Write a member LABEL, with PROPS, at LEVEL, after the subtree at POS.
Return a marker at the new heading."
  (save-excursion
    (goto-char pos)
    (org-end-of-subtree t t)
    (unless (bolp) (insert "\n"))
    (let ((at (point-marker)))
      (insert (make-string level ?*) " " label "\n" (org-truss--drawer props) "\n")
      at)))

(defun org-truss-add-member (parent label &optional props)
  "Write a member LABEL, with PROPS, as the last heading under PARENT.
PARENT is the position of a part or a member.  Return a marker at
the new heading."
  (org-truss--write-member-after parent (1+ (org-truss--level parent)) label props))

(defun org-truss-add-member-after (pos label &optional props)
  "Write a member LABEL, with PROPS, just after the member at POS, its sibling.
After what is nested under it too, so it comes next among its siblings.
Return a marker at the new heading."
  (org-truss--write-member-after pos (org-truss--level pos) label props))

(defun org-truss--put-grounds (pos refs sources)
  "Write TRUSS_GROUNDS at POS: links to the members REFS, then SOURCES.
With neither, take it away."
  (if (or refs sources)
      (org-entry-put pos "TRUSS_GROUNDS" (org-truss--grounds-value refs sources))
    (org-entry-delete pos "TRUSS_GROUNDS")))

(defun org-truss-set-grounds (pos refs)
  "Make the members REFS the grounds of the member at POS, or none if nil.
REFS are CUSTOM_IDs; see `org-truss-ensure-id'.  The sources TRUSS_GROUNDS
names besides stay."
  (org-truss--put-grounds pos refs (org-truss--grounds-sources (org-entry-get pos "TRUSS_GROUNDS"))))

(defun org-truss-set-sources (pos sources)
  "Make SOURCES what TRUSS_GROUNDS at POS names besides members, or nothing.
A link to a source, or words naming one that has no file.  The links to
members stay."
  (org-truss--put-grounds pos (org-truss--grounds-refs (org-entry-get pos "TRUSS_GROUNDS"))
                          (and sources (not (string-blank-p sources)) (string-trim sources))))

(defun org-truss-toggle-assumption (pos)
  "Tag the member at POS :assumption:, or take the tag off.  Return non-nil if on."
  (org-with-point-at pos
    (let ((on (not (member org-truss-assumption-tag (org-get-tags nil t)))))
      (org-toggle-tag org-truss-assumption-tag (if on 'on 'off))
      on)))

(defconst org-truss--id-re "^[ \t]*:CUSTOM_ID:[ \t]+m\\([0-9]+\\)[ \t]*$"
  "A CUSTOM_ID of the form org-truss gives: m and a number.")

(defun org-truss--next-id ()
  "Return a CUSTOM_ID no heading in the buffer has: m and the next number."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((case-fold-search t)
         (top 0))
     (while (re-search-forward org-truss--id-re nil t)
       (setq top (max top (string-to-number (match-string 1)))))
     (format "m%d" (1+ top)))))

(defun org-truss-ensure-id (pos)
  "Return the CUSTOM_ID of the member at POS, giving it one when it has none.
A new one is m and the next number free in the file, written first in its
property drawer, where the eye finds it.  Links and grounds point to a
member by it, so its heading can be rewritten freely."
  (let ((id (org-entry-get pos "CUSTOM_ID")))
    (if (and id (not (string-blank-p id)))
        (string-trim id)
      (let ((id (org-truss--next-id)))
        (org-with-point-at pos
          (let ((drawer (org-get-property-block)))
            (if drawer
                (save-excursion
                  (goto-char (car drawer))
                  (insert ":CUSTOM_ID: " id "\n"))
              (org-entry-put nil "CUSTOM_ID" id))))
        id))))

(defun org-truss-delete-member (pos)
  "Delete the member at POS, with what is nested under it, and its placings.
Every line that tells it, or a member under it, [[truss-include:m7]] on a
line of its own, goes too, wherever it is.  A ground that points to one is
left, and so is a link to one among other words, so the board shows as
broken what stood on it or told it.  Return the labels deleted."
  (let* ((end (save-excursion (goto-char pos) (org-end-of-subtree t t) (point)))
         (labels nil)
         (ids nil))
    (save-excursion
      (goto-char pos)
      (while (and (< (point) end) (re-search-forward org-heading-regexp end t))
        (let ((at (line-beginning-position)))
          (push (org-truss--label at) labels)
          (let ((id (org-entry-get at "CUSTOM_ID")))
            (when id (push (string-trim id) ids))))))
    (delete-region pos end)
    (when ids
      (org-with-wide-buffer
       (goto-char (point-min))
       (while (re-search-forward org-truss--include-line-re nil t)
         (when (member (org-truss--ref (match-string-no-properties 1)) ids)
           (delete-region (line-beginning-position)
                          (min (point-max) (1+ (line-end-position))))))))
    (nreverse labels)))

(defun org-truss--quote-bounds (pos)
  "Return (BEG . END) of the first quotation in the own text at POS, or nil.
A #+begin_quote block outside the public block, from its first line to the
end of its last."
  (let ((bounds (org-truss--own-bounds pos))
        (case-fold-search t)
        public found)
    (save-excursion
      (goto-char (car bounds))
      (while (and (not found) (< (point) (cdr bounds)))
        (cond ((looking-at org-truss--public-begin-re) (setq public t))
              ((looking-at org-truss--public-end-re) (setq public nil))
              ((and (not public) (looking-at "^[ \t]*#\\+begin_quote\\b"))
               (let ((beg (point)))
                 (when (re-search-forward "^[ \t]*#\\+end_quote[ \t]*$" (cdr bounds) t)
                   (setq found (cons beg (min (point-max) (1+ (line-end-position)))))))))
        (forward-line 1)))
    found))

(defun org-truss-set-quote (pos text)
  "Put TEXT under the member at POS as its quotation, in place of any there.
A #+begin_quote block in its own text: what the source says, in the
source's words, kept in the file as notes are.  A new one goes at the end
of its own text.  A line of TEXT that would read as a heading is moved off
the left margin.  Return non-nil when one was replaced."
  (let* ((body (replace-regexp-in-string "^\\*" " *" (string-trim text)))
         (block (concat "#+begin_quote\n" body "\n#+end_quote\n"))
         (old (org-truss--quote-bounds pos)))
    (save-excursion
      (if old
          (progn (goto-char (car old))
                 (delete-region (car old) (cdr old))
                 (insert block))
        (let ((heading-end (progn (goto-char pos) (line-end-position))))
          (goto-char (cdr (org-truss--own-bounds pos)))
          (skip-chars-backward " \t\n" heading-end)
          (insert "\n" (string-remove-suffix "\n" block))
          (when (eobp) (insert "\n")))))
    (and old t)))

(defun org-truss-public-body (pos)
  "Return where the text of the public block under the heading at POS starts.
It is what the reader is told there: a section's lead, or a member's words
for the reader.  When there is no block, an empty one is written first --
before the items that list members, or else at the end of the heading's
own text.  An empty block is given an empty line to write on."
  (save-excursion
    (let* ((bounds (org-truss--own-bounds pos))
           (end (copy-marker (cdr bounds)))
           (heading-end (progn (goto-char pos) (line-end-position)))
           (case-fold-search t))
      (goto-char (car bounds))
      (prog1
          (cond
           ((re-search-forward org-truss--public-begin-re end t)
            (forward-line 1)
            (when (looking-at org-truss--public-end-re)
              (insert "\n")
              (forward-line -1))
            (point))
           ((re-search-forward org-truss--include-line-re end t)
            (goto-char (line-beginning-position))
            (insert "#+begin_public\n\n#+end_public\n")
            (forward-line -2)
            (point))
           (t
            (goto-char end)
            (skip-chars-backward " \t\n" heading-end)
            (insert "\n#+begin_public\n\n#+end_public")
            (unless (looking-at "\n") (save-excursion (insert "\n")))
            (forward-line -1)
            (point)))
        (set-marker end nil)))))

(defun org-truss-drop-empty-public (beg end)
  "Take away the public blocks between BEG and END that hold nothing.
One left empty -- no title, no text -- tells the reader nothing, and would
only be in the way."
  (save-excursion
    (goto-char beg)
    (let ((end (copy-marker end))
          (case-fold-search t))
      (while (re-search-forward
              "^[ \t]*#\\+begin_public[ \t]*\n\\(?:[ \t]*\n\\)*[ \t]*#\\+end_public[ \t]*\\(?:\n\\|\\'\\)"
              end t)
        (replace-match ""))
      (set-marker end nil))))

(defun org-truss-refile (pos parent)
  "Move the heading at POS, with what is under it, to the end of PARENT.
PARENT is the position of another heading, outside the subtree at POS: a
part or a member for a member, a section for a section.  Its headings
take the levels of their new place.  Links and grounds point to a member
by its CUSTOM_ID, which goes with it, so they still find it.  Return a
marker at its heading."
  (let* ((end (save-excursion (goto-char pos) (org-end-of-subtree t t) (point)))
         (parent (copy-marker parent))
         (delta (- (1+ (org-truss--level parent)) (org-truss--level pos)))
         (text (buffer-substring-no-properties pos end)))
    (when (and (<= pos parent) (< parent end))
      (set-marker parent nil)
      (user-error "A heading cannot go under itself"))
    (unless (string-suffix-p "\n" text)
      (setq text (concat text "\n")))
    (setq text (replace-regexp-in-string
                "^\\(\\*+\\)\\([ \t]\\)"
                (lambda (m) (concat (make-string (+ (length (match-string 1 m)) delta) ?*)
                                    (match-string 2 m)))
                text t t))
    (delete-region pos end)
    (save-excursion
      (goto-char parent)
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n"))
      (let ((at (point-marker)))
        (insert text)
        (set-marker parent nil)
        at))))

(defun org-truss-rename (pos new)
  "Relabel the member at POS to NEW.
Links and grounds point to it by its CUSTOM_ID, so nothing else changes.
A label another member has is refused: a statement is written once."
  (let ((other (org-truss-member-by-label (org-truss-read) new)))
    (when (and other (/= (org-truss-member-pos other) pos))
      (user-error "A member is already labelled %s" new)))
  (org-with-point-at pos (org-edit-headline new)))

(defun org-truss-convert-references-in-buffer ()
  "Make every link and ground that names a member by its heading point by id.
A link [[*heading]] becomes [[#id]], and [[truss-include:*heading]]
\[[truss-include:id]], wherever it is, keeping its words, and so does a
ground in TRUSS_GROUNDS, keeping the sources named there; the member named
is given a CUSTOM_ID when it has none.  A heading no member has is left as
it is, and the checks show it as broken.  Return the number of references
changed."
  (let ((count 0)
        (case-fold-search nil)
        (id-of (lambda (label)
                 (let ((m (org-truss-member-by-label (org-truss-read) label)))
                   (and m (org-truss-ensure-id (org-truss-member-pos m)))))))
    (org-with-wide-buffer
     (goto-char (point-min))
     (while (re-search-forward (concat "\\[\\[\\(\\(?:" (regexp-quote org-truss-include-type)
                                       ":\\)?\\)\\*\\([^]]+\\)\\]")
                               nil t)
       ;; Giving the member an id writes above, so where the link is is
       ;; kept in markers.
       (unless (save-excursion (beginning-of-line) (looking-at-p "^[ \t]*:TRUSS_GROUNDS:"))
         (let* ((beg (copy-marker (match-beginning 0)))
                (end (copy-marker (match-end 0)))
                (include (not (string-empty-p (match-string-no-properties 1))))
                (id (save-excursion (funcall id-of (match-string-no-properties 2)))))
           (when id
             (goto-char beg)
             (delete-region beg end)
             (insert "[[" (if include (concat org-truss-include-type ":" id) (concat "#" id)) "]")
             (setq count (1+ count)))
           (goto-char end)
           (set-marker beg nil)
           (set-marker end nil))))
     (goto-char (point-min))
     (while (re-search-forward "^[ \t]*:TRUSS_GROUNDS:[ \t]+\\(.*?\\)[ \t]*$" nil t)
       (let* ((at (copy-marker (line-beginning-position)))
              (value (match-string-no-properties 1))
              (refs (org-truss--grounds-refs value))
              (new (mapcar (lambda (ref)
                             (or (and (string-prefix-p "*" ref)
                                      (save-excursion (funcall id-of (substring ref 1))))
                                 ref))
                           refs)))
         (unless (equal refs new)
           (setq count (+ count (seq-count #'identity (seq-mapn (lambda (a b) (not (equal a b)))
                                                                refs new))))
           (goto-char at)
           (org-back-to-heading t)
           (org-entry-put nil "TRUSS_GROUNDS"
                          (org-truss--grounds-value new (org-truss--grounds-sources value))))
         (goto-char at)
         (forward-line 1)
         (set-marker at nil))))
    count))

(provide 'org-truss-edit)

;;; org-truss-edit.el ends here

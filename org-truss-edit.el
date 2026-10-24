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
;; understand -- its text, other drawers -- as written.

(defun org-truss--snapshot (pos)
  "Return a snapshot of the subtree at POS.
A plist of :heading (the text after the stars), :props, :drawers, :notes
\(its text, comments and all), :links (the lines that tell members, of
their own) and :children."
  (let ((own (org-truss--own pos)))
    (save-excursion
      (goto-char pos)
      (looking-at "\\*+[ \t]+\\(.*\\)$")
      (list :heading (match-string-no-properties 1)
            :props (plist-get own :props)
            :drawers (plist-get own :drawers)
            :notes (plist-get own :notes)
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
        :drawers "" :notes "" :links nil :children nil))

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
  "Non-nil when SNAPSHOT holds text, besides the lines that tell members."
  (not (string-blank-p (plist-get snapshot :notes))))

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

(defun org-truss--add-line (pos line)
  "Write LINE under the heading at POS, after its last line of text."
  (save-excursion
    (let* ((bounds (org-truss--own-bounds pos))
           (heading-end (progn (goto-char pos) (line-end-position))))
      (goto-char (cdr bounds))
      (skip-chars-backward " \t\n" heading-end)
      (insert "\n" line)
      (unless (looking-at "\n")
        (insert "\n")))))

(defun org-truss-add-link (pos ref)
  "Tell the member REF under the heading at POS, after its last line of text.
In a list item of its own, - [[truss-include:REF]]; REF is the member's
CUSTOM_ID, see `org-truss-ensure-id'."
  (org-truss--add-line pos (string-remove-suffix "\n" (org-truss--link-item ref))))

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
  "Add a section called NAME, playing ROLES, under the section at PARENT.
ROLES are (KIND . ROLE), the roles it plays in the patterns of PARENT; it
goes where they list them, as `org-truss-add-heading' puts it, or else
last."
  (set-marker (org-truss-add-heading parent name (org-truss--role-props roles)) nil))

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

(defun org-truss-add-heading (parent label &optional props text)
  "Write a heading LABEL, with PROPS and TEXT under it, under PARENT.
PARENT is the position of any heading.  The new one goes where the
patterns of PARENT list the roles its PROPS give it: before the first
heading there that plays, in one of those patterns, a role listed after
its own; or else last.  Return a marker at it."
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
                           (org-truss--children parent))))
    (save-excursion
      (if before
          (goto-char before)
        (goto-char parent)
        (org-end-of-subtree t t)
        (unless (bolp) (insert "\n")))
      (let ((at (point-marker)))
        (insert (make-string (1+ (org-truss--level parent)) ?*) " " label "\n"
                (org-truss--drawer props) (or text "") "\n")
        at))))

(defun org-truss-add-place (pos kind role)
  "Put under the heading at POS a heading for ROLE of its pattern of KIND.
Named for the role in `org-truss-language' and playing it, it goes where
the pattern lists the role, as `org-truss-add-heading' puts it.  Return a
marker at it."
  (org-truss-add-heading pos (org-truss-role-label role)
                         (org-truss--role-props (list (cons kind role)))
                         (and org-truss-place-text-function
                              (funcall org-truss-place-text-function pos role))))

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

(defun org-truss-add-member (parent label &optional props)
  "Write a member LABEL, with PROPS, under PARENT, a part or a member.
Where the patterns there list the roles PROPS give it, as
`org-truss-add-heading' puts it, or else last.  Return a marker at the
new heading."
  (org-truss-add-heading parent label props))

(defun org-truss-add-ground (pos ref)
  "Make the member REF a ground of the heading at POS.
A link to it, # [[#REF]], on a comment line of its own after the
heading's last line of text, where the reader does not see it.  REF is a
CUSTOM_ID, or an item's target, pointed to as [[REF]]; see
`org-truss-ensure-id'."
  (org-truss--add-line pos (format "# [[%s]]" (if (org-truss--item-target-p ref)
                                                  ref
                                                (org-truss--target ref)))))

(defun org-truss--item-target-p (ref)
  "Non-nil when REF is the target of an item of a list, <<REF>>, in the buffer.
On an item's first line, after its bullet."
  (org-with-wide-buffer
   (goto-char (point-min))
   (re-search-forward (format "^[ \t]*\\(?:[-+*]\\|[0-9]+[.)]\\)[ \t].*<<%s>>" (regexp-quote ref))
                      nil t)))

(defun org-truss--pointing-line (pos ref)
  "Return (BEG . END) of the line pointing to REF in the own text at POS, or nil.
A line holding nothing but the link, [[#REF]] or [[REF]], as a list item
or not, as a comment or not."
  (let* ((bounds (org-truss--own-bounds pos))
         (re (format "^[ \t]*\\(?:#[ \t]+\\)?\\(?:[-+] \\|[0-9]+[.)] \\)?\\[\\[\\(?:%s\\|%s\\)\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*$"
                     (regexp-quote (org-truss--target ref)) (regexp-quote ref))))
    (save-excursion
      (goto-char (car bounds))
      (when (re-search-forward re (cdr bounds) t)
        (cons (line-beginning-position)
              (min (point-max) (1+ (line-end-position))))))))

(defun org-truss-remove-ground (pos ref)
  "Stop the heading at POS standing on the member REF.
The line that holds nothing but the link to it goes.  A link among other
words is left, for the words to be rewritten; nil is returned then."
  (let ((at (org-truss--pointing-line pos ref)))
    (when at
      (delete-region (car at) (cdr at))
      t)))

(defun org-truss-toggle-assumption (pos)
  "Tag the member at POS :assumption:, or take the tag off.  Return non-nil if on."
  (org-with-point-at pos
    (let ((on (not (member org-truss-assumption-tag (org-get-tags nil t)))))
      (org-toggle-tag org-truss-assumption-tag (if on 'on 'off))
      on)))

(defconst org-truss--id-re
  "^[ \t]*:CUSTOM_ID:[ \t]+m\\([0-9]+\\)[ \t]*$\\|<<m\\([0-9]+\\)>>"
  "An id of the form org-truss gives, m and a number: a heading's CUSTOM_ID,
or an item's target.")

(defun org-truss--next-id ()
  "Return an id no heading or item in the buffer has: m and the next number."
  (org-with-wide-buffer
   (goto-char (point-min))
   (let ((case-fold-search t)
         (top 0))
     (while (re-search-forward org-truss--id-re nil t)
       (setq top (max top (string-to-number (or (match-string 1) (match-string 2))))))
     (format "m%d" (1+ top)))))

(defun org-truss-ensure-id (pos)
  "Return the CUSTOM_ID of the member at POS, giving it one when it has none.
A new one is m and the next number free in the file, written first in its
property drawer, where the eye finds it.  Links and grounds point to a
member by it, so its heading can be rewritten freely.  A member written
as an item of a list is given a target, <<m7>>, where its words start."
  (if (save-excursion (goto-char pos) (not (org-at-heading-p)))
      (org-truss--ensure-item-id pos)
    (org-truss--ensure-heading-id pos)))

(defun org-truss--ensure-item-id (pos)
  "Return the target of the item at POS, giving it one when it has none."
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
  "Return the CUSTOM_ID of the heading at POS, giving it one when it has none."
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

(defun org-truss-lead-line (pos)
  "Return where a lead is written under the heading at POS, or nil.
Before the first line that tells a member, on an empty line written for
it: what is written there opens what the heading tells.  Nil when no line
tells one."
  (save-excursion
    (let ((bounds (org-truss--own-bounds pos)))
      (goto-char (car bounds))
      (when (re-search-forward org-truss--include-line-re (cdr bounds) t)
        (goto-char (line-beginning-position))
        (insert "\n")
        (1- (point))))))

(defun org-truss--public-converted (start end label)
  "Return the own text between START and END written without a public block.
LABEL is the heading's.  What was the file's alone -- the text outside
the public block, the lines telling members aside -- goes into a comment
block; the public block's text is the text the reader is told; its
title, when it is not LABEL, is kept on a comment line above that, for
the heading to be rewritten by hand; the lines telling members follow, as
they did, a link in a sentence of the file's text as an item of its own.
Nil when there is nothing to change: no public block, and no text but
comments."
  (let ((case-fold-search t)
        (state 'text)
        block title head notes public items found plain)
    (save-excursion
      (goto-char start)
      (while (< (point) end)
        (let* ((line (buffer-substring-no-properties (point) (min end (line-end-position))))
               (raw (concat line "\n")))
          (pcase state
            ('properties (push raw head)
                         (when (string-match-p org-truss--end-re line) (setq state 'text)))
            ('drawer (push raw head)
                     (when (string-match-p org-truss--end-re line) (setq state 'text)))
            ('public (if (string-match-p "^[ \t]*#\\+end_public\\b" line)
                         (setq state 'text)
                       (push raw public)))
            ('comment (unless (string-match-p "^[ \t]*#\\+end_comment\\b" line)
                        (push raw notes))
                      (when (string-match-p "^[ \t]*#\\+end_comment\\b" line)
                        (setq state 'text)))
            ('block (push raw notes)
                    (when (string-match-p (format "^[ \t]*#\\+end_%s\\b" (regexp-quote block)) line)
                      (setq state 'text)))
            (_
             (cond
              ((string-match-p org-truss--properties-re line)
               (push raw head)
               (setq state 'properties))
              ((and (string-match-p org-truss--drawer-re line)
                    (not (string-match-p org-truss--end-re line)))
               (push raw head)
               (setq state 'drawer))
              ((string-match "^[ \t]*#\\+begin_public\\(?:[ \t]+\\(.*?\\)\\)?[ \t]*$" line)
               (setq title (match-string 1 line)
                     found t
                     state 'public))
              ((string-match-p org-truss--comment-begin-re line)
               (setq state 'comment))
              ((string-match-p org-truss--include-line-re line)
               (push raw items))
              (t
               (when (string-match org-truss--block-begin-re line)
                 (setq block (match-string 1 line)
                       state 'block))
               (unless (or (string-blank-p line) (string-match-p org-truss--comment-line-re line))
                 (setq plain t))
               (push raw notes)
               (dolist (link (org-truss--include-links-in line))
                 (push (format "- %s\n" link) items))))))
          (forward-line 1))))
    (let ((notes (string-trim (apply #'concat (nreverse notes)) "\\(?:[ \t]*\n\\)+" "[ \t\n]+"))
          (public (string-trim (apply #'concat (nreverse public)) "\\(?:[ \t]*\n\\)+" "[ \t\n]+"))
          (title (and title (not (string-blank-p title)) (not (equal (string-trim title) label))
                      (string-trim title))))
      (when (or found plain)
        (concat (apply #'concat (nreverse head))
                (string-join
                 (delq nil
                       (list (and (not (string-empty-p notes))
                                  (concat "#+begin_comment\n" notes "\n#+end_comment\n"))
                             (and (or title (not (string-empty-p public)))
                                  (concat (if title
                                              (format (org-truss--pick "# Title for the reader: %s\n"
                                                                       "# 読み手向けの見出し: %s\n")
                                                      title)
                                            "")
                                          (if (string-empty-p public) "" (concat public "\n"))))
                             (and items (apply #'concat (nreverse items)))))
                 "\n")
                (if (string-suffix-p "\n\n" (buffer-substring-no-properties start end)) "\n" ""))))))

(defun org-truss-convert-public-in-buffer ()
  "Write every heading's text as the reader is now told it, without public blocks.
The text under a heading is told, a comment left out, where a public
block's alone was before: so what each heading had outside its public
block goes into a comment block, and what its public block said is its
text; see `org-truss--public-converted'.  A buffer with no public block
is taken to be written as it is now already, and is left as it is, since
its text could not be told from notes.  Return the number of headings
changed."
  (let ((count 0)
        (case-fold-search t))
    (org-with-wide-buffer
     (goto-char (point-min))
     (when (re-search-forward org-truss--public-begin-re nil t)
       ;; From the last heading up, so what is rewritten moves nothing
       ;; still to come.
       (goto-char (point-max))
       (while (re-search-backward org-outline-regexp-bol nil t)
         (let* ((bounds (org-truss--own-bounds (point)))
                (new (org-truss--public-converted (car bounds) (cdr bounds)
                                                  (org-truss--heading-text))))
           (when new
             (save-excursion
               (delete-region (car bounds) (cdr bounds))
               (goto-char (car bounds))
               (insert new))
             (setq count (1+ count)))))))
    count))

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
\[[truss-include:id]], wherever it is, keeping its words; the member named
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
    count))

(defconst org-truss--any-link-re "\\[\\[[^]\n]+\\]\\(?:\\[[^]\n]*\\]\\)?\\]"
  "Any Org link, with its words or without.")

(defun org-truss-convert-grounds-in-buffer ()
  "Move what each TRUSS_GROUNDS says into its heading's text, and drop it.
Grounds are read from a heading's text alone.  Each link there -- to a
member, to a source -- goes on a line of its own after the heading's last
line of text; the words naming what has no
file go on a line after them.  Words are no grounds: a heading they alone
grounded, with nothing else in its text to stand on, is tagged
:assumption:, taken as given, as what no text records is.  Return the
number of headings changed."
  (let ((count 0)
        (case-fold-search t))
    (org-with-wide-buffer
     (goto-char (point-min))
     (while (re-search-forward "^[ \t]*:TRUSS_GROUNDS:[ \t]*\\(.*?\\)[ \t]*$" nil t)
       (let* ((value (match-string-no-properties 1))
              (pos (progn (org-back-to-heading t) (point-marker)))
              (links (let ((from 0) found)
                       (while (string-match org-truss--any-link-re value from)
                         (push (match-string 0 value) found)
                         (setq from (match-end 0)))
                       (nreverse found)))
              (words (string-trim (replace-regexp-in-string
                                   "[ \t]+" " "
                                   (replace-regexp-in-string org-truss--any-link-re "" value)))))
         (org-entry-delete pos "TRUSS_GROUNDS")
         (dolist (link links)
           (org-truss--add-line pos link))
         (unless (string-empty-p words)
           (org-truss--add-line pos words)
           (unless (or links
                       (let ((text (org-truss--text (org-truss--own pos))))
                         (or (org-truss--refs-in text)
                             (org-truss--source-links-in text)
                             (org-truss--quotes-in text))))
             (org-with-point-at pos
               (org-toggle-tag org-truss-assumption-tag 'on))))
         (setq count (1+ count))
         (goto-char pos)
         (set-marker pos nil))))
    count))

(provide 'org-truss-edit)

;;; org-truss-edit.el ends here

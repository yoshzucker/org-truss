;;; org-truss-edit.el --- The edits made to a truss file  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The edits org-truss makes to a truss file, each at a position in its
;; buffer: sections rearranged, links and properties written, members
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
:public-raw, :links (the link-only items), :wordings (theirs) and :children."
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
            :wordings (plist-get own :wordings)
            :children (mapcar #'org-truss--snapshot (org-truss--children pos))))))

(defun org-truss--snapshot-roles (snapshot)
  "Return the roles SNAPSHOT's TRUSS_ROLE names."
  (org-truss--roles (cdr (assoc "TRUSS_ROLE" (plist-get snapshot :props)))))

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
          (mapconcat (lambda (ref)
                       (org-truss--link-item
                        ref (cdr (assoc ref (plist-get snapshot :wordings)))))
                     (plist-get snapshot :links) "")
          "\n"
          (mapconcat (lambda (c) (org-truss--serialize c (1+ level)))
                     (plist-get snapshot :children) "")))

(defun org-truss--link-item (ref &optional wording)
  "Return the list item that lists the member REF, told in WORDING if given."
  (if wording
      (format "- [[%s][%s]]\n" (org-truss--target ref) wording)
    (format "- [[%s]]\n" (org-truss--target ref))))

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
        :props (list (cons "TRUSS_ROLE" (symbol-name (car place))))
        :drawers "" :notes "" :public-raw "" :links nil :children nil))

(defun org-truss-apply-section-telling (pos pattern)
  "Give the section at POS the telling PATTERN, and a section for each place.
A section already there that shares a role with one of the pattern's places
takes that place as it is -- heading, roles and all it holds -- so nothing
written is changed; a section for the place, named in `org-truss-language',
is added only where none does.  A section that shares no role, or roles
with more than one place, is kept after the rest -- outside the pattern, to
be moved by hand.  Links on the section itself stay on it."
  (let* ((news (mapcar #'org-truss--place-snapshot (org-truss-pattern-places pattern)))
         (snapshot (org-truss--snapshot pos))
         (olds (plist-get snapshot :children))
         (place-of (lambda (old)
                     (let ((hits (seq-filter
                                  (lambda (new)
                                    (seq-intersection (org-truss--snapshot-roles old)
                                                      (org-truss--snapshot-roles new)))
                                  news)))
                       (and (= (length hits) 1) (car hits))))))
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
      (setq snapshot (plist-put snapshot :wordings
                                (append (plist-get snapshot :wordings)
                                        (mapcan (lambda (s) (copy-sequence (plist-get s :wordings)))
                                                below))))
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
            (wordings (mapcan (lambda (s) (copy-sequence (plist-get s :wordings))) all))
            (parent (copy-marker parent)))
        (save-excursion
          (goto-char pos)
          (delete-region pos (progn (org-end-of-subtree t t) (point))))
        (dolist (ref links)
          (org-truss-add-link parent ref (cdr (assoc ref wordings))))
        (set-marker parent nil)
        nil))))

;;;; Links and properties

(defun org-truss-add-link (pos ref &optional wording)
  "List the member REF in the section at POS, after its last item.
REF is the member's CUSTOM_ID; see `org-truss-ensure-id'.  WORDING, if
given, is what the reader is told there instead of its heading."
  (save-excursion
    (let* ((bounds (org-truss--own-bounds pos))
           (heading-end (progn (goto-char pos) (line-end-position))))
      (goto-char (cdr bounds))
      (skip-chars-backward " \t\n" heading-end)
      (insert "\n" (string-remove-suffix "\n" (org-truss--link-item ref wording)))
      (unless (looking-at "\n")
        (insert "\n")))))

(defun org-truss-remove-link (pos ref)
  "Stop listing the member REF in the section at POS."
  (let ((line (org-truss--link-line pos ref)))
    (when line
      (delete-region (car line) (cdr line))
      t)))

(defun org-truss-link-wording (pos ref)
  "Return the words the section at POS tells the member REF in, or nil."
  (cdr (assoc ref (plist-get (org-truss--own pos) :wordings))))

(defun org-truss-set-wording (pos ref wording)
  "Tell the member REF in WORDING in the section at POS, where it is listed.
With WORDING nil or blank, the section tells it in its own heading again.
Return non-nil when the section lists REF."
  (let ((line (org-truss--link-line pos ref))
        (wording (and wording (not (string-blank-p wording)) (string-trim wording))))
    (when (and wording (string-match-p "[][\n]" wording))
      (user-error "Words for a link cannot hold brackets or line breaks"))
    (when line
      (save-excursion
        (goto-char (car line))
        (let ((indent (progn (looking-at "[ \t]*") (match-string 0))))
          (delete-region (car line) (cdr line))
          (insert indent (org-truss--link-item ref wording))))
      t)))

(defun org-truss-replace-link (pos old new)
  "Make the item listing OLD in the section at POS list NEW, where it stands.
Return non-nil when there was such an item."
  (let ((line (org-truss--link-line pos old))
        (case-fold-search nil))
    (when line
      (save-excursion
        (goto-char (car line))
        (re-search-forward (concat "\\[\\[" (regexp-quote (org-truss--target old)) "\\]")
                           (cdr line))
        (replace-match (concat "[[" (org-truss--target new) "]") t t))
      t)))

(defun org-truss-move-link (from ref to)
  "Move the member REF from the section at FROM to the section at TO."
  (let ((to (copy-marker to))
        (wording (org-truss-link-wording from ref)))
    (when (org-truss-remove-link from ref)
      (org-truss-add-link to ref wording))
    (set-marker to nil)))

(defun org-truss-shift-link (pos ref delta)
  "Move the item for REF in the section at POS by DELTA items, -1 or 1."
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

(defun org-truss-add-section (parent name roles)
  "Add a section called NAME, answering ROLES, as the last one under PARENT."
  (save-excursion
    (let ((level (1+ (org-truss--level parent))))
      (goto-char parent)
      (org-end-of-subtree t t)
      (unless (bolp) (insert "\n"))
      (insert (org-truss--serialize
               (list :heading name
                     :props (and roles (list (cons "TRUSS_ROLE"
                                                   (mapconcat #'symbol-name roles " "))))
                     :drawers "" :notes "" :public-raw "" :links nil :children nil)
               level)))))

(defun org-truss-set-roles (pos roles)
  "Make the heading at POS answer ROLES, or no role when ROLES is nil."
  (if roles
      (org-entry-put pos "TRUSS_ROLE" (mapconcat #'symbol-name roles " "))
    (org-entry-delete pos "TRUSS_ROLE")))

(defun org-truss-set-pattern (pos kind pattern)
  "Give the cluster at POS, a member or a section, PATTERN of KIND.
KIND is `logic', `aspects' or `telling'; see `org-truss-patterns'.  With
PATTERN nil it has none of that kind: a member then reads as why ›
reasons, aspects ask for nothing, and it is told conclusion first."
  (let ((property (alist-get kind org-truss-pattern-properties)))
    (if pattern
        (org-entry-put pos property (symbol-name pattern))
      (org-entry-delete pos property))))

(defun org-truss-start-cluster (pos home)
  "Write the logic a member written in HOME starts a cluster with, at POS.
Only when the member at POS has none written; see `org-truss-default-logic'.
Return the pattern written, or nil."
  (unless (org-entry-get pos "TRUSS_LOGIC")
    (let ((logic (org-truss-default-logic home)))
      (org-truss-set-pattern pos 'logic logic)
      logic)))

(defun org-truss-add-places (pos gaps section)
  "Put under the heading at POS a heading for each place GAPS names.
GAPS are (ROLE . SHORT-BY), as `org-truss-gaps' gives them: as many
headings for a role as it is short by, each named for its role in
`org-truss-language' and filling it, after what is there.  They are
sections when SECTION is non-nil, and members, to be written over, when it
is not.  A pattern asks for places a writer cannot be expected to make
by hand; this makes them.  Return the number made."
  (let ((n 0))
    (pcase-dolist (`(,role . ,short) gaps)
      (dotimes (_ short)
        (setq n (1+ n))
        (if section
            (org-truss-add-section pos (org-truss-role-label role) (list role))
          (org-truss-add-member pos (org-truss-role-label role)
                                (list (cons "TRUSS_ROLE" (symbol-name role)))))))
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
PARENT is the position of a part, a field or a member.  Return a marker at
the new heading."
  (org-truss--write-member-after parent (1+ (org-truss--level parent)) label props))

(defun org-truss-add-member-after (pos label &optional props)
  "Write a member LABEL, with PROPS, just after the member at POS, its sibling.
After what is nested under it too, so it comes next among its siblings.
Return a marker at the new heading."
  (org-truss--write-member-after pos (org-truss--level pos) label props))

(defun org-truss-set-grounds (pos refs)
  "Make the members REFS the grounds of the member at POS, or none if nil.
REFS are CUSTOM_IDs; see `org-truss-ensure-id'."
  (if refs
      (org-entry-put pos "TRUSS_GROUNDS" (org-truss--grounds-value refs))
    (org-entry-delete pos "TRUSS_GROUNDS")))

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
Every link item in the structure that points to it, or to a member under
it, goes too.  A ground that points to one is left, so the board shows as
a broken ground what stood on it.  Return the labels deleted."
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
    (let ((structure (org-truss--part-pos "structure")))
      (when (and structure ids)
        (save-excursion
          (let ((stop (copy-marker (save-excursion (goto-char structure)
                                                   (org-end-of-subtree t t) (point)))))
            (goto-char structure)
            (while (re-search-forward org-truss--link-item-re stop t)
              (when (member (org-truss--ref (match-string-no-properties 1)) ids)
                (delete-region (line-beginning-position)
                               (min (point-max) (1+ (line-end-position))))))
            (set-marker stop nil)))))
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
           ((re-search-forward org-truss--link-item-re end t)
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

(defun org-truss-set-kind (pos kind &optional value)
  "Make the member at POS a KIND of member, by writing what makes it one.
KIND is `fact', `assumption', `question' or `claim'.  A fact takes VALUE as
its TRUSS_SOURCE; an assumption, as whom to confirm it with, nobody when
VALUE is nil.  What would make it another kind is taken off: the tags, and
the source of a claim.  A source stays on an assumption or a question, as
a note of where it was thought to come from; whom to confirm with goes once
it is a fact or a claim."
  (org-with-point-at pos
    (dolist (tag (list org-truss-assumption-tag org-truss-question-tag))
      (when (member tag (org-get-tags nil t))
        (org-toggle-tag tag 'off)))
    (pcase kind
      ('assumption (org-toggle-tag org-truss-assumption-tag 'on))
      ('question (org-toggle-tag org-truss-question-tag 'on))))
  (pcase kind
    ('fact (org-entry-put pos "TRUSS_SOURCE" value))
    ('claim (org-entry-delete pos "TRUSS_SOURCE")))
  (cond ((memq kind '(fact claim)) (org-entry-delete pos "TRUSS_CONFIRM"))
        ((and (eq kind 'assumption) value) (org-entry-put pos "TRUSS_CONFIRM" value))
        ((eq kind 'assumption) (org-entry-delete pos "TRUSS_CONFIRM"))))

(defun org-truss-refile-member (pos parent)
  "Move the member at POS, with what is nested under it, to the end of PARENT.
PARENT is the position of a part, a field or another member, outside the
subtree at POS.  Its headings take the levels of their new place.  Links
and grounds point to it by its CUSTOM_ID, which goes with it, so they
still find it.  Return a marker at its heading."
  (let* ((end (save-excursion (goto-char pos) (org-end-of-subtree t t) (point)))
         (parent (copy-marker parent))
         (delta (- (1+ (org-truss--level parent)) (org-truss--level pos)))
         (text (buffer-substring-no-properties pos end)))
    (when (and (<= pos parent) (< parent end))
      (set-marker parent nil)
      (user-error "A member cannot go under itself"))
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
A link [[*heading]] in the structure becomes [[#id]], keeping its words,
and a heading in TRUSS_GROUNDS -- a link to it, or a name in the old
`;'-separated list -- becomes [[#id]]; the member named is given a
CUSTOM_ID when it has none.  A heading no member has is left as it is, and
the checks show it as broken.  Return the number of references changed."
  (let ((count 0)
        (case-fold-search nil)
        (id-of (lambda (label)
                 (let ((m (org-truss-member-by-label (org-truss-read) label)))
                   (and m (org-truss-ensure-id (org-truss-member-pos m)))))))
    (org-with-wide-buffer
     (let ((structure (org-truss--part-pos "structure")))
       (when structure
         (goto-char structure)
         (while (re-search-forward "\\[\\[\\*\\([^]]+\\)\\]" nil t)
           ;; Giving the member an id writes above, so where the link is
           ;; is kept in markers.
           (let* ((beg (copy-marker (match-beginning 0)))
                  (end (copy-marker (match-end 0)))
                  (id (save-excursion (funcall id-of (match-string-no-properties 1)))))
             (when id
               (goto-char beg)
               (delete-region beg end)
               (insert "[[#" id "]")
               (setq count (1+ count)))
             (goto-char end)
             (set-marker beg nil)
             (set-marker end nil)))))
     (goto-char (point-min))
     (while (re-search-forward "^[ \t]*:TRUSS_GROUNDS:[ \t]+\\(.*?\\)[ \t]*$" nil t)
       (let* ((at (copy-marker (line-beginning-position)))
              (refs (org-truss--grounds-refs (match-string-no-properties 1)))
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
           (org-entry-put nil "TRUSS_GROUNDS" (org-truss--grounds-value new)))
         (goto-char at)
         (forward-line 1)
         (set-marker at nil))))
    count))

(provide 'org-truss-edit)

;;; org-truss-edit.el ends here

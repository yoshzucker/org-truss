;;; org-truss-draw.el --- A truss file drawn as the board's text  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; How the board is drawn: a model, read from a truss file, made into lines
;; of text, each carrying what it stands for.  `org-truss-board-text' is the
;; way in.  Nothing here reads a key or changes the file; the board's mode
;; and commands are in org-truss-board.el.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-export)

(defface org-truss-section '((t :inherit bold))
  "Face for a section's label on the board."
  :group 'org-truss)

(defface org-truss-dim '((t :inherit shadow))
  "Face for what is said about a line rather than the line itself."
  :group 'org-truss)

(defface org-truss-tentative '((t :inherit italic))
  "Face for what marks an assumption, taken as given."
  :group 'org-truss)

(defface org-truss-attention '((t :inherit warning))
  "Face for what wants doing: a missing role, missing grounds, a broken link."
  :group 'org-truss)

(defface org-truss-reader '((t))
  "Face for what the reader sees as a heading, in the board's right column.
What the reader sees as body text takes `org-truss-dim', as the notes under
a heading do in the middle column."
  :group 'org-truss)

(defface org-truss-untold '((t :inherit org-truss-dim :slant italic))
  "Face for what the reader would see of a member the document does not tell.
The right of a member placed nowhere, nor under one placed."
  :group 'org-truss)

(defface org-truss-branch '((t :inherit org-truss-dim))
  "Face for the tree that joins a member to the members nested under it.
The tree of the brief's fields and of the sections keeps the default face,
so the two trees read apart where they meet."
  :group 'org-truss)

;; Every line has three columns.  The left is what the board says the line
;; is, in its own words.  The middle, from one column shared by every line,
;; is the file's words -- headings, labels, the title -- as written.  The
;; right is what the reader sees of it, so the document can be read down the
;; page, and a member's prose beside its logic where it is written; nothing
;; where the reader is told nothing of it.  What the board says about
;; how a section or an argument is arranged -- the pattern it follows --
;; goes on the line below, so the left stays narrow and the middle stays
;; close to the tree.  A line drawn whole has what is written under its
;; heading follow it: what stays in the file in the middle, the rest of what
;; the reader sees on the right; the pattern stays right under the heading's
;; line, beside them.

(defcustom org-truss-board-middle-width nil
  "Width of the board's middle, the file's words, before the right begins.
The middle starts in one column, just right of the widest of the board's
own words, and the right starts this far right of that column.  Nil gives
the middle half of the window right of that column, never less than 20,
so the middle and the right share it evenly; a number fixes it.  Words too
long for the middle are cut short, the whole of them in the tooltip; a
line drawn whole is broken to fit it."
  :type '(choice (const :tag "Half of the window" nil) integer)
  :group 'org-truss)

(defcustom org-truss-board-right-width nil
  "Width at which a line drawn whole breaks its right, what the reader sees.
Nil fits it to the window, from where the right starts to the window's
edge, never narrower than 20 columns; a number fixes it.  On one line
nothing is broken: a line runs on and the window cuts it."
  :type '(choice (const :tag "Fit the window" nil) integer)
  :group 'org-truss)

(defcustom org-truss-board-image-height 15
  "Most lines a picture takes on a line of the board drawn whole.
A picture linked on a line of its own is drawn in its column, as wide as
the column and no taller than this; elsewhere it is its file's name."
  :type 'integer
  :group 'org-truss)

(defcustom org-truss-board-marks
  '((ground . "⏚") (built . "↥") (section . "▤") (item . "•"))
  "The marks of the lines that are an end of a link, by what they name.
Each line is under a member or a section and names a member, or a
section, and its mark says what what it names is to the one above:
`ground', what the member above stands on -- a member its TRUSS_GROUNDS
links to, a source it names there or links to in its text, the words it
quotes -- drawn below it; `built', a member standing
on the member above, which names it in its own -- drawn below it all the
same, so the mark points up; `section', the section that lists the
member above, where the document tells it; and `item', in the structure,
a member the section above lists, as the file writes it, - [[#m7]].  A
line with no mark is written there.  One character each, as wide as a
letter where the board is drawn, keeps the tree in line."
  :type '(alist :key-type symbol :value-type string)
  :group 'org-truss)

(defcustom org-truss-board-fold-limit 5
  "How many members a field of the brief or the subject shows before folding.
A field holding more starts folded on the board, as one line that says how
many it holds; \\<org-truss-board-mode-map>\\[org-truss-board-fold] unfolds it."
  :type 'integer
  :group 'org-truss)

(defvar org-truss--folding nil
  "The folds of the board being drawn; see `org-truss--folds'.")

(defun org-truss--folded-p (key default)
  "Non-nil when the line whose fold is KEY is folded; DEFAULT if not toggled."
  (let ((state (assoc key org-truss--folding)))
    (if state (eq (cdr state) 'closed) default)))

(defun org-truss--fold-mark (n)
  "Return what a folded line shows of the N members it hides."
  (propertize (format " ▸%d" n) 'face 'org-truss-dim))

(defvar org-truss--middle-width 40
  "Width given the middle, the file's words, while a board is drawn.")

(defvar org-truss--right-width 60
  "Width a line drawn whole breaks its right at, while a board is drawn.")

(defvar org-truss--wrapping nil
  "The lines of the board being drawn the other way; see `org-truss--wraps'.")

(defvar org-truss--middle-column 0
  "The column the middle starts at, while a board is drawn.")

(defvar org-truss--images nil
  "Non-nil while a board is drawn where pictures can be shown.")

(defvar org-truss--base-directory nil
  "The directory of the truss file whose board is being drawn.
A link to a file by a relative path is read from it.")

(defvar org-truss--whole nil
  "Non-nil while lines are drawn whole, with the text under each heading.")

(defvar org-truss--in-structure nil
  "Non-nil while the structure is drawn.
There a member brings only what the document tells with it: not its
grounds, nor where it is used, nor what its patterns still ask for.
Elsewhere it brings all of them, and its right is what the reader is told
of it all the same.")

(defvar org-truss--uses nil
  "While a board is drawn, how each member is used, by the member.
\(SECTIONS . MEMBERS): the sections that list it, and the members it is a
ground of, each in the order of the file.")

(defvar org-truss--placed nil
  "While a board is drawn, the members the document tells.
Those its sections list, with what is nested under them; see
`org-truss-told'.")

(defvar org-truss--order 'written
  "Where a board opens a member a section lists: `written' or `told'.
As written, where it is written, with what is nested under it, and the
structure lists it on one line.  As told, under the section, with all it
brings where it is written -- its uses, its grounds, its gaps -- and
where it is written it is one line.  Either can be unfolded where it is
one line.")

(defvar org-truss--model nil
  "The model of the board being drawn.")

(defvar org-truss--checks nil
  "What `org-truss-checks' says of the board being drawn.")

;;;; Drawing

(defun org-truss--line (left &optional middle right item)
  "Return one board line, laid out later by `org-truss-board-text'.
LEFT is what the board says the line is.  MIDDLE is the file's words for
it, RIGHT what the reader sees of it, or what a check says.  ITEM is what
the line stands for, kept as a text property for the commands; its :why,
if any, is the line's help."
  (list :left left :middle middle
        :right (and right (not (string-empty-p right)) right)
        :item item))

(defun org-truss--with-id (line id)
  "Return LINE naming a member by ID, at the end of its left, or LINE as it is.
ID is how a call to the member is written, [[#m9]], or the member itself
is pointed to, #m9; see `org-truss--id-text'."
  (if id (append line (list :id (propertize id 'face 'org-truss-dim))) line))

(defun org-truss--id-text (member &optional ref)
  "Return how the board names MEMBER by its CUSTOM_ID, or nil when it has none.
REF, when the line calls it -- a section's link, a ground -- as the call
is written, [[#m9]]; else as anything points to it, #m9, where it is
written."
  (cond (ref (format "[[%s]]" (org-truss--target ref)))
        ((org-truss-member-id member) (concat "#" (org-truss-member-id member)))))

(defun org-truss--leader (width)
  "Return WIDTH columns that lead the eye from the board's words to the file's.
A space at each end; dots between, when there is room for one."
  (let ((dots (/ (- width 2) (char-width ?·))))
    (if (< dots 1)
        (make-string width ?\s)
      (concat " " (propertize (make-string dots ?·) 'face 'org-truss-dim)
              (make-string (- width 1 (* dots (char-width ?·))) ?\s)))))

(defun org-truss--lay-out (line column)
  "Return LINE as text, with its middle starting at COLUMN.
When something follows on the right, the middle is cut short to leave it
its column; so it is on a line marked :cut, which names a member written
elsewhere and leaves the right empty, as the reader is told nothing there.
The member the line names by its id, if any, has it at the end of the
left, just before the middle."
  (let* ((left (plist-get line :left))
         (id (plist-get line :id))
         (right (plist-get line :right))
         (room (- org-truss--middle-width 2))
         (middle (let ((middle (plist-get line :middle)))
                   (if (and (or right (plist-get line :cut)) middle (> (string-width middle) room))
                       (propertize (truncate-string-to-width middle room nil nil "…")
                                   'help-echo middle)
                     middle)))
         (why (plist-get (plist-get line :item) :why))
         (gap (- column (string-width left) (if id (1+ (string-width id)) 0)))
         (out (if (and middle (or right (not (string-empty-p middle))))
                  (concat left
                          (if (or (plist-get line :bare) (string-blank-p left))
                              (make-string gap ?\s)
                            (org-truss--leader gap))
                          (if id (concat id " ") "")
                          middle)
                left)))
    (when right
      (let ((gap (make-string (max 2 (- (+ column org-truss--middle-width)
                                         (string-width out)))
                               ?\s)))
        ;; A slice of a picture is one character as wide as the picture, so
        ;; counting characters would not reach the column; the gap is drawn
        ;; to it instead.
        (when (text-property-not-all 0 (length out) 'display nil out)
          (setq gap (propertize gap 'display
                                `(space :align-to ,(+ column org-truss--middle-width)))))
        (setq out (concat out gap right))))
    ;; A line holding a slice is as high as the slice, with no spacing
    ;; added, so the slices of a picture meet.
    (setq out (propertize (concat out (if (text-property-not-all 0 (length out) 'display nil out)
                                          (propertize "\n" 'line-height t)
                                        "\n"))
                          'org-truss-item (plist-get line :item)))
    (if why (propertize out 'help-echo why) out)))

(defun org-truss--one-line (text)
  "Return TEXT with its lines joined, as a filled paragraph reads.
Between two wide characters a line break is dropped; elsewhere it is a space."
  (let ((lines (split-string (string-trim text) "[ \t]*\n[ \t]*")))
    (seq-reduce (lambda (acc line)
                  (if (string-empty-p acc)
                      line
                    (concat acc
                            (if (and (> (char-width (aref acc (1- (length acc)))) 1)
                                     (not (string-empty-p line))
                                     (> (char-width (aref line 0)) 1))
                                ""
                              " ")
                            line)))
                lines "")))

(defun org-truss--role-names (cluster)
  "Return the roles CLUSTER plays in the patterns above, as the board names them.
Joined, in the order of their kinds; nil when it plays none."
  (let ((roles (org-truss-cluster-roles cluster)))
    (and roles (mapconcat (lambda (kind)
                            (let ((role (alist-get kind roles)))
                              (and role (org-truss-role-name role))))
                          (seq-filter (lambda (kind) (alist-get kind roles)) org-truss-pattern-kinds)
                          " · "))))

(defun org-truss--role-word (model member)
  "Return the board's word for MEMBER of MODEL, on the left of its line.
The roles it plays in the patterns of the member above, or `member' when
it plays none; then [no role] when it plays none of a pattern above it,
[assumed] when it is tagged :assumption:, and [no grounds] when it must
have grounds and lacks them, each in its face."
  (concat (or (org-truss--role-names member) "member")
          (if (org-truss--no-role-p member) (propertize " [no role]" 'face 'org-truss-attention) "")
          (if (org-truss-assumption-p member) (propertize " [assumed]" 'face 'org-truss-tentative) "")
          (if (org-truss-missing-grounds model member)
              (propertize " [no grounds]" 'face 'org-truss-attention)
            "")))

(defun org-truss--link-text (text)
  "Return TEXT with each link read as its description, or else its target.
A link to a file without one reads as the file's name."
  (replace-regexp-in-string
   "\\[\\[\\*?\\([^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]"
   (lambda (link)
     (let ((target (match-string 1 link)))
       (or (match-string 2 link)
           (save-match-data
             (and (string-match "\\`\\(?:file:\\|\\.\\.?/\\)\\([^:]+\\)" target)
                  (file-name-nondirectory (org-link-unescape (match-string 1 target)))))
           target)))
   text t t))

(defun org-truss--picture (line)
  "Return the file LINE shows, when it is a link to a picture and nothing else.
The file as it is found from the truss file's directory, and nil unless
it can be read."
  (and (string-match (concat "\\`[ \t]*\\[\\[\\(?:file:\\([^]:]+\\)\\|\\(\\.\\.?/[^]:]+\\)\\)"
                             "\\]\\][ \t]*\\'")
                     line)
       (let ((file (expand-file-name (org-link-unescape (or (match-string 1 line)
                                                            (match-string 2 line)))
                                     org-truss--base-directory)))
         (and (string-match-p (image-file-name-regexp) file)
              (file-readable-p file)
              file))))

(defun org-truss--picture-lines (file width)
  "Return the picture in FILE as the lines it takes in a column WIDTH wide.
It is scaled to the column, no taller than `org-truss-board-image-height'
lines, and cut into slices a line high, one to each line, so it sits in
its column as text does and the tree beside it runs on down.  Nil where
no picture can be shown."
  (when org-truss--images
    (let* ((high (frame-char-height))
           ;; Centred on the line, a slice as high as the text fills the
           ;; line and no more; sat on the baseline, as by default, it would
           ;; hang below and push the next slice down.
           (image (create-image file nil nil
                                :max-width (* width (frame-char-width))
                                :max-height (* org-truss-board-image-height high)
                                :ascent 'center))
           (size (image-size image t)))
      (cl-loop for y from 0 below (cdr size) by high
               collect (propertize " " 'display
                                   (list (list 'slice 0 y (car size) high) image)
                                   'help-echo (abbreviate-file-name file))))))

(defun org-truss--break (line width)
  "Return LINE broken into pieces no wider than WIDTH.
A word written in narrow letters is not split: the break goes back to the
space before it.  Closing punctuation does not start a line: the character
before it goes down with it."
  (let (out)
    (while (> (string-width line) width)
      (let* ((cut (max 1 (length (truncate-string-to-width line width))))
             (cut (if (and (> cut 1)
                           (memq (aref line cut) '(?、 ?。 ?， ?． ?） ?」 ?』 ?】 ?〕)))
                      (1- cut)
                    cut))
             (narrow (lambda (i) (and (< 0 i (length line))
                                      (not (eq (aref line i) ?\s))
                                      (= (char-width (aref line i)) 1))))
             (space (and (funcall narrow cut) (funcall narrow (1- cut))
                         (string-match-p " [^ ]*\\'" (substring line 0 cut))))
             (at (if (and space (> space 0)) space cut)))
        (push (string-trim-right (substring line 0 at)) out)
        (setq line (string-trim-left (substring line at)))))
    (nreverse (cons line out))))

(defun org-truss--fill (text width)
  "Return TEXT as lines no wider than WIDTH, as it reads.
A paragraph of prose is joined and broken again.  A table, a block or a list
keeps its lines; a table's are cut where they run over.  Links read as their
descriptions, and a blank line stays between paragraphs.  A picture linked
on a line of its own is drawn, where the board can show one, on the lines
it takes; see `org-truss--picture-lines'."
  (let (out)
    (dolist (para (split-string (string-trim text) "\n[ \t]*\n" t))
      (when out (push "" out))
      (let ((lines (split-string para "\n")))
        (dolist (line (if (seq-some (lambda (l)
                                      (or (string-match-p "\\`[ \t]*\\(|\\|#\\+\\|[-+] \\|[0-9]+[.)] \\)" l)
                                          (org-truss--picture l)))
                                    lines)
                          (mapcan (lambda (l)
                                    (let ((picture (org-truss--picture l)))
                                      (or (and picture (org-truss--picture-lines picture width))
                                          (let ((l (org-truss--link-text l)))
                                            (if (string-match-p "\\`[ \t]*|" l)
                                                (list (truncate-string-to-width l width))
                                              (org-truss--break l width))))))
                                  lines)
                        (org-truss--break (org-truss--one-line (org-truss--link-text para))
                                          width)))
          (push line out))))
    (nreverse out)))

(defun org-truss--reader-text (seen)
  "Return what the reader sees of SEEN, a (TITLE . BODY) pair, on one line.
Its title when it has one; otherwise the first paragraph of its body, or the
first line of it when it opens with a table or a block.  Links read as their
descriptions.  A title is in the face of a heading, body text in the face of
body text."
  (let* ((title (car seen))
         (body (string-trim (or (cdr seen) "")))
         (text (cond ((and title (not (string-blank-p title))) title)
                     ((string-empty-p body) nil)
                     ((string-match-p "\\`[ \t]*\\(|\\|#\\+\\)" body)
                      (car (split-string body "\n")))
                     (t (org-truss--one-line (car (split-string body "\n[ \t]*\n")))))))
    (and text (propertize (org-truss--link-text text)
                          'face (if (and title (not (string-blank-p title)))
                                    'org-truss-reader
                                  'org-truss-dim)))))

(defun org-truss--reader-lines (seen)
  "Return what the reader sees of SEEN, a (TITLE . BODY) pair, as lines.
The first goes on the heading's own line, the rest under it.  Without entry
text there is one: its title, or the start of its body.  The title is in the
face of a heading, the body in the face of body text."
  (if (not org-truss--whole)
      (list (org-truss--reader-text seen))
    (let ((title (car seen))
          (body (mapcar (lambda (line) (propertize line 'face 'org-truss-dim))
                        (org-truss--fill (or (cdr seen) "") org-truss--right-width))))
      (if (and title (not (string-blank-p title)))
          (append (org-truss--break (propertize title 'face 'org-truss-reader)
                                    org-truss--right-width)
                  body)
        body))))

(defun org-truss--member-reader (member &optional wording where)
  "Return what the reader sees of MEMBER as lines, the first for its own line.
What `org-truss-member-told' says it is told in at WHERE, `before' or
`after' what is under it -- WORDING when a section tells it in words of its
own and it has no block for WHERE -- and with WHERE nil its public block,
or its label; `noexport' when the reader sees nothing of it."
  (if (org-truss-noexport-p member)
      (list (propertize "noexport" 'face 'org-truss-dim))
    (org-truss--reader-lines (org-truss-member-told member where wording))))

(defun org-truss--level-face (level)
  "Return the face Org gives the words of a heading at LEVEL.
As `org-get-level-face' works it out, for odd levels only and for faces
that cycle or stop at the last."
  (let ((n (if org-odd-levels-only (1+ (/ level 2)) level)))
    (if org-cycle-level-faces
        (nth (% (1- n) org-n-level-faces) org-level-faces)
      (nth (1- (min n org-n-level-faces)) org-level-faces))))

(defun org-truss--member-words (member)
  "Return MEMBER's heading as the board draws it: in the face the file gives
a heading of its level.  The board colours it itself, rather than copy the
file's, which is there only where the file has been shown."
  (propertize (org-truss-member-label member)
              'face (org-truss--level-face (org-truss-member-level member))))

(defun org-truss--label-lines (label)
  "Return LABEL as the lines it is drawn on.
One, cut short if need be; drawn whole, as many as it takes to break it to
the room of the middle, since the line is then read rather than scanned."
  (if org-truss--whole
      (org-truss--break label (- org-truss--middle-width 2))
    (list label)))

(defun org-truss--lines-under-heading (left more notes below item &optional head stem)
  "Return the lines under a heading's own line on the board.
HEAD, if any, is the line that says how what is under the heading is
arranged.  Drawn whole, MORE, the rest of the heading's own words, and
then NOTES, what is written under the heading and stays in the file, go in
the middle; BELOW, the rest of what the reader sees, on the right.  LEFT
starts each line, and STEM, when given, each line below HEAD, or every
line without one: the line of the tree down to what branches off under
the heading.  ITEM is the heading's line's, kept under a key of its own.

HEAD's words take the left of the first of these lines, so they stay right
under the heading's line.  When they are too wide for the left they take
the line after the heading's own words instead, and the middle leaves
that line to them."
  (if (not org-truss--whole)
      (and head (list head))
    (let* ((notes (mapcar (lambda (line) (propertize line 'face 'org-truss-dim))
                          (org-truss--fill (or notes "") (- org-truss--middle-width 2))))
           (wide (and head (> (+ (string-width (plist-get head :left)) 2)
                              org-truss--middle-column)))
           (at (cond (wide (length more)) (head 0) (t -1)))
           (middle (append more (and wide (list nil)) notes)))
      (cl-loop for i below (max (length middle) (length below) (1+ at))
               collect (append (if (= i at)
                                   (org-truss--line (plist-get head :left) (nth i middle)
                                                    (nth i below) (plist-get head :item))
                                 (org-truss--line (if (and stem (> i at)) stem left)
                                                  (or (nth i middle) "") (nth i below)
                                                  (plist-put (copy-sequence item) :key
                                                             (append (plist-get item :key)
                                                                     (list 'text i)))))
                               '(:bare t))))))

(defun org-truss--whole-lines (line)
  "Return LINE as the lines it takes drawn whole.
Its middle and its right are each broken to their column, and what does
not fit goes on lines of its own below, which start with LINE's :under,
the tree on its left going on down.  A heading and what the reader sees
of it are broken where they are drawn, to keep them in order with what is
under the heading; this breaks the rest: a ground, what a check lists."
  (let* ((room (- org-truss--middle-width 2))
         (middle (plist-get line :middle))
         (right (plist-get line :right))
         (middles (and middle (org-truss--break middle room)))
         (rights (and right (org-truss--break right org-truss--right-width)))
         (item (plist-get line :item)))
    (if (and (null (cdr middles)) (null (cdr rights)))
        (list line)
      (cons (plist-put (plist-put (copy-sequence line) :middle (car middles)) :right (car rights))
            (cl-loop for i from 1 below (max (length middles) (length rights))
                     collect (append (org-truss--line
                                      (or (plist-get line :under) "")
                                      (or (nth i middles) "") (nth i rights)
                                      (and item
                                           (plist-put (copy-sequence item) :key
                                                      (append (plist-get item :key)
                                                              (list 'wrap i)))))
                                     '(:bare t)))))))

(defconst org-truss--mark-help
  '((ground . "Its grounds: what the member above stands on, in its TRUSS_GROUNDS or its text")
    (built . "Built on it: this member stands on the member above, which its TRUSS_GROUNDS names")
    (section . "Its section: this section lists the member above, and the document tells it here")
    (item . "An item of the section above: it lists this member, - [[#id]], and the document tells it here"))
  "What the mark of each kind of line naming the other end of a link says.")

(defun org-truss--mark (kind)
  "Return the mark of a line naming the other end of a link of KIND, and a space.
See `org-truss-board-marks'; the mouse on it says what it means."
  (concat (propertize (or (alist-get kind org-truss-board-marks) "?")
                      'face 'org-truss-dim
                      'help-echo (alist-get kind org-truss--mark-help))
          " "))

(defun org-truss--use-lines (model member stem key)
  "Return a line for each use of MEMBER of MODEL.
Each section that lists it, by its roles and its heading, marked as its
section, and then each member it is a ground of, by its roles and its
heading, marked as built on it: the other end of a link, as the line of a
ground it stands on is of one.  In the structure, where it is drawn under
the section, the section goes without saying.  STEM starts each; KEY is
MEMBER's line's.  Each goes to what it names."
  (let ((use (and org-truss--uses (gethash member org-truss--uses)))
        (root (org-truss-model-structure model)))
    (mapcar
     (lambda (line) (append line (list :under stem :cut t)))
     (append
      (mapcar (lambda (section)
                (org-truss--line
                 (concat stem (org-truss--mark 'section)
                         (if (eq section root) "Structure" (org-truss--section-word section)))
                 (and (not (eq section root))
                      (propertize (org-truss-section-label section) 'face 'org-truss-dim))
                 nil
                 (list :type 'use :pos (org-truss-section-pos section)
                       :key (append key (list 'use (org-truss-section-pos section))))))
              (and (not org-truss--in-structure) (car use)))
      (mapcar (lambda (user)
                (org-truss--line
                 (concat stem (org-truss--mark 'built) (org-truss--role-word model user))
                 (propertize (org-truss-member-label user) 'face 'org-truss-dim)
                 nil
                 (list :type 'use :pos (org-truss-member-pos user)
                       :key (append key (list 'use (org-truss-member-pos user))))))
              (cdr use))))))

(defun org-truss--told-wording (member)
  "Return the words the section that lists MEMBER tells it in, or nil."
  (let ((section (car (car (and org-truss--uses (gethash member org-truss--uses))))))
    (and section (org-truss-member-id member)
         (org-truss-section-wording section (org-truss-member-id member)))))

(defun org-truss--untold (lines)
  "Return LINES, what the reader would see, in the face of what is not told."
  (mapcar (lambda (line) (and line (propertize line 'face 'org-truss-untold))) lines))

(defun org-truss--member-uses (model)
  "Return how each member of MODEL is used, as `org-truss--uses' keeps it."
  (let ((uses (make-hash-table :test #'eq))
        (root (org-truss-model-structure model))
        (cell (lambda (m uses) (or (gethash m uses) (puthash m (cons nil nil) uses)))))
    (when root
      (dolist (section (cons root (org-truss-sections model)))
        (dolist (ref (org-truss-section-links section))
          (let ((m (org-truss-member-by-ref model ref)))
            (when m
              (let ((use (funcall cell m uses)))
                (setcar use (append (car use) (list section)))))))))
    (dolist (m (org-truss-model-all model))
      (dolist (ref (org-truss-member-grounds m))
        (let ((ground (org-truss-member-by-ref model ref)))
          (when ground
            (let ((use (funcall cell ground uses)))
              (setcdr use (append (cdr use) (list m))))))))
    uses))

(defun org-truss--branch (indent last)
  "Return how the lines of a member nested under another start.
INDENT starts the other's lines.  A cons (LINE . UNDER) for
`org-truss--member-lines': LINE branches off to the member, and UNDER
carries the tree down past it to the next, unless the member is the LAST."
  (cons (concat indent (propertize (if last "└ " "├ ") 'face 'org-truss-branch))
        (concat indent (propertize (if last "  " "│ ") 'face 'org-truss-branch))))

(defun org-truss--point-name (member)
  "Return what MEMBER's telling pattern calls the place that is the member.
Answer, umbrella, conclusion: the place it fills in its own pattern."
  (let ((place (seq-find (lambda (place) (memq :point (cdr place)))
                         (org-truss-pattern-places (or (org-truss-member-telling member) 'first)))))
    (if place (org-truss-role-name (car place)) "point")))

(defun org-truss--told-below (lines told left under item)
  "Return LINES, those under a member's own, then the member told below them.
TOLD is nil when the member is told above them, and LINES come back as
they are.  Else TOLD is what the reader is told of it, as lines, and they
come after LINES: the first starting with LEFT, the rest with UNDER, the
tree on the left going on down.  A line runs down the start of the right
of LINES, from the member's own line, and turns into the first of them,
so the words it holds line up with theirs.  ITEM is what they stand for."
  (if (null told)
      lines
    (let ((bar (propertize "│" 'face 'org-truss-branch))
          (i 0))
      (append
       (mapcar (lambda (line)
                 (let ((right (plist-get line :right)))
                   (plist-put (copy-sequence line) :right (if right (concat bar " " right) bar))))
               lines)
       (mapcar (lambda (text)
                 (prog1
                     (org-truss--line
                      (if (= i 0) left under)
                      nil
                      (concat (if (= i 0) (propertize "└ " 'face 'org-truss-branch) "  ") text)
                      (if (= i 0)
                          item
                        (plist-put (copy-sequence item) :key
                                   (append (plist-get item :key) (list 'wrap i)))))
                   (setq i (1+ i))))
               told)))))

(defun org-truss--ground-line (stem key left middle item &optional id)
  "Return a line naming what a member stands on, below it.
STEM starts it, with the mark of a ground and LEFT; MIDDLE names it; ITEM
is what it stands for, under KEY, and ID how it is called, if it is."
  (append (org-truss--with-id
           (org-truss--line (concat stem (org-truss--mark 'ground) left)
                            (and middle (propertize middle 'face 'org-truss-dim))
                            nil (plist-put item :key key))
           id)
          (list :under stem :cut t)))

(defun org-truss--grounds-lines (model member stem key)
  "Return a line for each thing MEMBER of MODEL stands on, below it.
The members its TRUSS_GROUNDS links to, each said to be a broken link when
it is no member, and to have no grounds when it does not hold; then the
sources TRUSS_GROUNDS names besides, the first link to a source in its
text, and the words it quotes, a link among them that points to nothing
said not to be found.  STEM starts each; KEY is MEMBER's line's."
  (let* ((pos (org-truss-member-pos member))
         (missing (mapcar #'cdr (seq-filter (lambda (b) (eq (car b) member))
                                            (plist-get org-truss--checks :broken-sources))))
         (found-p (lambda (text) (not (seq-some (lambda (link) (string-search link text)) missing)))))
    (append
     (mapcar (lambda (ref)
               (let ((ground (org-truss-member-by-ref model ref)))
                 (org-truss--ground-line
                  stem (append key (list 'ground ref))
                  (cond ((null ground) (propertize "broken ground" 'face 'org-truss-attention))
                        ((org-truss-holds-p ground) "ground")
                        (t (concat "ground" (propertize " [no grounds]" 'face 'org-truss-attention))))
                  (if ground (org-truss-member-label ground) (format "[[%s]]" (org-truss--target ref)))
                  (list :type 'member :pos (if ground (org-truss-member-pos ground) pos)
                        :label (and ground (org-truss-member-label ground))
                        :claim pos :ground ref)
                  (and ground (org-truss--id-text ground ref)))))
             (org-truss-member-grounds member))
     (mapcar (lambda (source)
               (org-truss--ground-line stem (append key (list 'source (car source)))
                                       (concat (symbol-name (car source))
                                               (if (funcall found-p (cdr source)) ""
                                                 (propertize " [not found]" 'face 'org-truss-attention)))
                                       (org-truss--one-line (org-truss--link-text (cdr source)))
                                       (list :type 'member :pos pos)))
             (delq nil (list (and (org-truss-member-sources member)
                                  (cons 'source (org-truss-member-sources member)))
                             (and (org-truss-member-cited member)
                                  (cons 'cited (org-truss-member-cited member)))
                             (and (org-truss-member-quoted member)
                                  (cons 'quote (org-truss-member-quoted member)))))))))

(defun org-truss--member-lines (model member indent key
                                      &optional link section marker wording)
  "Return board lines for MEMBER and what is nested under it.
INDENT starts each line: a string, or a cons (LINE . UNDER) for a member
nested under another, LINE starting its own line and UNDER the lines under
it, as `org-truss--branch' makes them.  The members nested under MEMBER
branch off right under it, as the sections of the structure do; its
patterns head them, and its grounds go in further, as a section's links do.
KEY identifies the line across redraws.  LINK, the reference the
section's link makes, and SECTION are set when a section lists MEMBER, so
the line can be moved; WORDING, when that section tells it in words of
its own.  MARKER is how the reader sees it begin: its number or bullet
when it is a part of the member above's breakdown, written out as a list,
and the role it plays when that breakdown labels its parts.

The right is what the document tells of it: what its telling pattern
tells it in where it comes, and, when the pattern closes with it again, a
line after what is under it.  Where it is opened, as `org-truss--order'
says, where it is used follows it, then what it stands on, each line
marked as `org-truss-board-marks' says, and the roles its patterns ask for
and it lacks; where it is not, it starts folded, to one line.  In the
structure, `org-truss--in-structure', only what the document tells comes
with it besides.  Elsewhere its right is in the face of what is not told
while the document does not tell it.  A member the file has below one its
parent's telling pattern tells after it is marked."
  (let* ((under (if (consp indent) (cdr indent) indent))
         (indent (if (consp indent) (car indent) indent))
         (in-structure org-truss--in-structure)
         (patterned (org-truss-cluster-patterns member))
         (label (org-truss--label-lines (org-truss--member-words member)))
         ;; A marker opens the first line, and the lines after it are
         ;; indented as far, as a list item's are.
         (hang (if marker (string-width marker) 0))
         (marked (lambda (lines)
                   (if (and marker (car lines))
                       (cons (concat (propertize marker 'face (get-text-property 0 'face (car lines)))
                                     (car lines))
                             (mapcar (lambda (line)
                                       (if (string-empty-p line) line
                                         (concat (make-string hang ?\s) line)))
                                     (cdr lines)))
                     lines)))
         (first (org-truss-told-first-p member))
         (up (org-truss-parent model member))
         ;; A part of a breakdown written out as a list opens its item,
         ;; whatever its telling pattern.
         (item-of-list (and up (org-truss-breakdown-list up)))
         (children (org-truss-member-children member))
         (nested (length (mapcan #'org-truss--subtree children)))
         ;; It is opened in one place, by the order the board is drawn
         ;; in, and starts folded in the other; see `org-truss--order'.
         (elsewhere (if (eq org-truss--order 'told)
                        (and (not in-structure)
                             (car (and org-truss--uses (gethash member org-truss--uses))))
                      (and in-structure link)))
         (folded (and (> nested 0) (org-truss--folded-p key (and elsewhere t))))
         (shown (and (not folded) children))
         ;; What it brings where it is written -- its uses, its grounds, its
         ;; gaps -- it brings where it is opened; not where it is one line.
         (full (and (not folded) (not elsewhere)
                    (or (not in-structure) (eq org-truss--order 'told))))
         ;; A member told after what is under it is told, in the document,
         ;; below it: the right shows its words there, a line running
         ;; down to them from its own line.  Not one folded, whose words
         ;; go on its own line.
         (last-told (and (not first) (not folded) (not item-of-list)
                         (not (org-truss-noexport-p member))))
         ;; Where it is written, the words the section placing it tells it
         ;; in are its all the same; what no section places is not told.
         (wording (or wording (and (not in-structure) (org-truss--told-wording member))))
         (untold (if (and (not in-structure) (not (memq member org-truss--placed)))
                     #'org-truss--untold
                   #'identity))
         (reader (if last-told
                     (list (propertize "┐" 'face 'org-truss-branch))
                   ;; Folded, one told after what is under it has the words
                   ;; it is told in there on its own line.
                   (let ((org-truss--right-width (- org-truss--right-width hang))
                         (where (if (and folded (not first) (not item-of-list)) 'after 'before)))
                     (funcall untold
                              (funcall marked (org-truss--member-reader member wording where))))))
         (answer (and last-told
                      (let ((org-truss--right-width (- org-truss--right-width hang 2)))
                        (funcall untold
                                 (funcall marked (org-truss--member-reader member wording 'after))))))
         (as-list (org-truss-breakdown-list member))
         (n 0)
         ;; What comes between its patterns and the members branching off
         ;; below -- its notes, its grounds -- has the tree's line run past.
         (stem (concat under (if shown (propertize "│ " 'face 'org-truss-branch) "  ")))
         (item (append (list :type 'member :pos (org-truss-member-pos member)
                             :label (org-truss-member-label member)
                             :link link :section section :key key)
                       (and (> nested 0) (list :fold key :folded folded))))
         (above (cdr (assq member (plist-get org-truss--checks :out-of-order))))
         (late (and above
                    (format "%s tells it before %s, which is above it in the file"
                            (org-truss-pattern-name (org-truss-member-telling up))
                            (org-truss-member-label above)))))
    (cons
     ;; Called from the structure, it names the member as the link does;
     ;; where it is written, by its id.  Nested under a member called
     ;; there, it is not called itself, and names nothing.
     (org-truss--with-id
      (org-truss--line
       (concat indent
               ;; Listed by a section, it is an end of a link, marked as
               ;; the lines naming one are.
               (if link (org-truss--mark 'item) "")
               (org-truss--role-word model member)
               (if folded (org-truss--fold-mark nested) "")
               (if late (propertize " ⚠" 'face 'org-truss-attention) ""))
       (car label)
       (car reader)
       (if late (append item (list :why late)) item))
      (and (or link (not in-structure)) (org-truss--id-text member link)))
     (org-truss--told-below
      (append
       (org-truss--lines-under-heading
        under (cdr label) (org-truss-member-notes member) (cdr reader) item
        (and patterned (not folded)
             (org-truss--line
              (concat under (propertize (format "(%s)" (org-truss-patterns-label member))
                                        'face 'org-truss-dim))
              nil nil (list :type 'member :pos (org-truss-member-pos member)
                            :key (append key '(pattern)))))
        stem)
       (and full (org-truss--use-lines model member stem key))
       (and full (org-truss--grounds-lines model member stem key))
       ;; Under that line, what is under the member leaves its columns at
       ;; the start of the right.
       (let ((i 0)
             (org-truss--right-width (if last-told (- org-truss--right-width 2) org-truss--right-width)))
         (mapcan (lambda (child)
                   (org-truss--member-lines model child
                                            (org-truss--branch under (= (setq i (1+ i))
                                                                        (length shown)))
                                            (append key (list (org-truss-member-label child)))
                                            nil nil
                                            (and (not (org-truss-noexport-p child))
                                                 (if as-list
                                                     (let ((marker (org-truss--list-marker
                                                                    member child (setq n (1+ n)))))
                                                       (concat (car marker) (cdr marker)))
                                                   (let ((label (org-truss--role-label member child)))
                                                     (and (not (string-empty-p label)) label))))))
                 shown))
       ;; A pattern that closes with the member again tells it once more
       ;; after what is under it.
       ;; Drawn whole, its words are broken here, so the lines they go on
       ;; carry the tree on the left down.
       (and first (not folded) (org-truss-told-again-p member)
            (not (org-truss-noexport-p member))
            (let* ((told (org-truss-member-told member 'after wording))
                   (said (org-truss--reader-text
                          (cons nil (if (string-empty-p (or (cdr told) "")) (car told) (cdr told)))))
                   (i -1))
              (mapcar (lambda (words)
                        (setq i (1+ i))
                        (org-truss--line (concat under "  " (if (= i 0)
                                                                (propertize "again" 'face 'org-truss-dim)
                                                              ""))
                                         nil words
                                         (list :type 'member :pos (org-truss-member-pos member)
                                               :key (append key (if (= i 0) '(again)
                                                                  (list 'again 'wrap i))))))
                      (funcall untold
                               (cond ((null said) nil)
                                     (org-truss--whole (org-truss--break said org-truss--right-width))
                                     (t (list said)))))))
       (mapcar (lambda (gap)
                 (org-truss--line
                  (concat under "  " (org-truss--gap-text member gap))
                  nil nil (list :type 'member :pos (org-truss-member-pos member)
                                :gap (cons (car gap) (cadr gap))
                                :key (append key (list 'gap (car gap) (cadr gap))))))
               (and full (org-truss-gaps member))))
      answer
      (concat under "  " (propertize (downcase (org-truss--point-name member)) 'face 'org-truss-dim))
      under
      (list :type 'member :pos (org-truss-member-pos member) :key (append key '(answer)))))))

(defun org-truss--links-lines (model section indent path)
  "Return board lines for the members SECTION of MODEL lists."
  (mapcan (lambda (ref)
            (let ((member (org-truss-member-by-ref model ref))
                  (key (list 'link path ref)))
              (if member
                  (org-truss--member-lines model member indent key ref
                                           (org-truss-section-pos section) nil
                                           (org-truss-section-wording section ref))
                (list (org-truss--line
                       (concat indent (org-truss--mark 'item)
                               (propertize "broken link" 'face 'org-truss-attention))
                       (propertize (format "[[%s]]" (org-truss--target ref)) 'face 'org-truss-attention)
                       nil (list :type 'broken :pos (org-truss-section-pos section)
                                 :link ref :section (org-truss-section-pos section) :key key))))))
          (org-truss-section-links section)))

(defun org-truss--pattern-line (cluster indent item)
  "Return the line naming the patterns CLUSTER follows, or nil if it follows none.
CLUSTER is a section, or the brief or the subject: its breakdown and its
telling pattern, which give what is below them their roles.
It goes under CLUSTER's own line, at INDENT.  ITEM is CLUSTER's line's,
kept under a key of its own."
  (let ((label (org-truss-patterns-label cluster)))
    (and label
         (org-truss--line
          (concat indent (propertize (format "(%s)" label) 'face 'org-truss-dim))
          nil nil (plist-put (copy-sequence item) :key
                             (append (plist-get item :key) '(pattern)))))))

(defun org-truss--asking (cluster gap)
  "Return the name of the pattern of CLUSTER that asks for GAP, or nil.
Nil when CLUSTER has that pattern alone, and no other could be asking."
  (and (cdr (org-truss-cluster-patterns cluster))
       (org-truss-pattern-name (org-truss-cluster-pattern cluster (car gap)))))

(defun org-truss--gap-text (cluster gap)
  "Return how the board shows GAP of CLUSTER, (KIND ROLE . SHORT-BY).
The role, how many more, and, when CLUSTER has more than one pattern, the
one that asks for it."
  (let ((asking (org-truss--asking cluster gap)))
    (concat (propertize (format "%s —%s" (org-truss-role-name (cadr gap))
                                (if (> (cddr gap) 1) (format " ×%d" (cddr gap)) ""))
                        'face 'org-truss-attention)
            (if asking (propertize (format " (%s)" asking) 'face 'org-truss-dim) ""))))

(defun org-truss--section-gap-lines (section indent item)
  "Return a line for each role SECTION's patterns ask for and no section right
below plays, at INDENT; ITEM is SECTION's line's.  On one, a new section
plays that role."
  (mapcar (lambda (gap)
            (org-truss--line
             (concat indent (org-truss--gap-text section gap))
             nil nil (append (list :gap (cons (car gap) (cadr gap))
                                   :key (append (plist-get item :key)
                                                (list 'gap (car gap) (cadr gap))))
                             item)))
          (cdr (assq section (plist-get org-truss--checks :gaps)))))

(defun org-truss--no-role-p (cluster)
  "Non-nil when the board being drawn finds CLUSTER playing no role it should."
  (assq cluster (plist-get org-truss--checks :no-role)))

(defun org-truss--section-word (section)
  "Return the board's word for SECTION, on the left of its line: its roles.
`no role', in the face of what wants doing, when it plays none of a
pattern of the section above; else `section' when it plays none."
  (let ((roles (org-truss--role-names section)))
    (concat (or roles "section")
            (if (org-truss--no-role-p section)
                (propertize " [no role]" 'face 'org-truss-attention)
              ""))))

(defun org-truss--section-lines (model section prefix last path parent)
  "Return board lines for SECTION and the sections below it.
PREFIX draws the tree to the left; LAST says SECTION ends its siblings.
PATH is the labels from the root, which identifies the line across redraws.
PARENT is the section above.  A section that comes below one the
parent's telling pattern tells after is marked."
  (let* ((path (append path (list (org-truss-section-label section))))
         (inner (concat prefix (if last "  " "│ ")))
         (children (org-truss-section-children section))
         ;; Its notes and links have the line to the sections below run past.
         (stem (concat inner (if children "│ " "  ")))
         (above (cdr (assq section (plist-get org-truss--checks :out-of-order))))
         (late (and above
                    (format "%s tells it before %s, which is above it in the file"
                            (org-truss-pattern-name (org-truss-section-telling parent))
                            (org-truss-section-label above))))
         (stray (cadr (org-truss--no-role-p section)))
         (why (string-join
               (delq nil (list (and stray
                                    (format "Plays no role of %s; %s gives it one"
                                            (org-truss-pattern-label (org-truss-cluster-pattern parent stray))
                                            (substitute-command-keys "\\[org-truss-board-roles]")))
                               late))
               ". "))
         (public (org-truss-section-public section))
         (title (org-truss-section-title section))
         (label (org-truss--label-lines
                 (propertize (org-truss-section-label section) 'face 'org-truss-section)))
         (reader (org-truss--reader-lines (cons title (cdr public))))
         (item (list :type 'section :pos (org-truss-section-pos section)
                     :label (org-truss-section-label section)
                     :key (list 'section path))))
    (append
     (list (org-truss--line (concat prefix (if last "└ " "├ ")
                                    (org-truss--section-word section)
                                    (if late (propertize " ⚠" 'face 'org-truss-attention) ""))
                            (car label)
                            (car reader)
                            (append item (and (not (string-empty-p why)) (list :why why)))))
     (org-truss--lines-under-heading inner (cdr label) (org-truss-section-notes section) (cdr reader) item
                             (org-truss--pattern-line section inner item) stem)
     (org-truss--links-lines model section stem path)
     (let ((n (length children)) (i 0))
       (mapcan (lambda (child)
                 (setq i (1+ i))
                 (org-truss--section-lines model child inner (= i n) path section))
               children))
     (org-truss--section-gap-lines section (concat inner "  ") item))))

(defun org-truss--check-heading (name)
  "Return the line that heads the check NAME, saying what it finds on hover."
  (org-truss--line (propertize (concat " " name) 'face 'org-truss-section
                               'help-echo (org-truss-check-about name))))

(defun org-truss--part-of (cluster)
  "Return the part CLUSTER is in: `brief', `subject', `members' or `structure'."
  (cond ((org-truss-member-p cluster) (org-truss-member-home cluster))
        ((org-truss-section-p cluster) 'structure)
        ((org-truss-field-p cluster) (org-truss-field-part cluster))
        ((org-truss-part-p cluster) (org-truss-part-name cluster))))

(defun org-truss--check-line (model cluster key right)
  "Return the line naming CLUSTER of MODEL under a check, keyed KEY.
Its board word on the left, its heading in the middle, RIGHT on the right;
RET on it goes to the heading."
  (let ((root (eq cluster (org-truss-model-structure model))))
    (org-truss--with-id
     (org-truss--line
      (concat "   " (cond ((org-truss-member-p cluster) (org-truss--role-word model cluster))
                         (root "Structure")
                         ((org-truss-section-p cluster) (org-truss--section-word cluster))
                         ((org-truss-field-p cluster) (org-truss-field-name cluster))
                         (t (capitalize (symbol-name (org-truss-part-name cluster))))))
      (cond ((org-truss-member-p cluster) (org-truss--member-words cluster))
            ((or root (org-truss-part-p cluster)) nil)
            (t (org-truss-cluster-label cluster)))
      (and right (propertize right 'face 'org-truss-attention))
      (append (list :type (cond ((org-truss-member-p cluster) 'member)
                                ((org-truss-section-p cluster) 'section)
                                (t 'brief))
                    :pos (org-truss-cluster-pos cluster)
                    :label (org-truss-cluster-label cluster)
                    :key key)
              (and root (list :root t))))
     (and (org-truss-member-p cluster) (org-truss--id-text cluster)))))

(defun org-truss--check-group (model name entries right)
  "Return the lines of the check NAME for ENTRIES, or nil when there are none.
Each entry is (CLUSTER . WHAT), and RIGHT, given an entry, says what is
wrong there."
  (when entries
    (let ((i 0))
      (cons (org-truss--check-heading name)
            (mapcar (lambda (entry)
                      (org-truss--check-line model (car entry)
                                             (list name (org-truss-cluster-label (car entry))
                                                   (setq i (1+ i)))
                                             (funcall right entry)))
                    entries)))))

(defun org-truss--check-lines (model checks part)
  "Return the lines of what CHECKS finds in PART of MODEL, check by check.
Each thing is listed in the part it is found in, under the check that
finds it, as `org-truss-check-descriptions' names them."
  (let* ((in (lambda (entries) (seq-filter (lambda (e) (eq (org-truss--part-of (car e)) part))
                                           entries)))
         (refs (lambda (refs) (mapconcat (lambda (ref) (format "[[%s]]" (org-truss--target ref)))
                                         refs " ")))
         (broken (and (eq part 'structure) (plist-get checks :broken-links)))
         (duplicates (and (eq part 'structure) (plist-get checks :duplicates)))
         (lines
          (append
           (org-truss--check-group
            model "Broken links" (funcall in (append (plist-get checks :broken-grounds)
                                                     (plist-get checks :broken-sources)))
            (lambda (e) (format "%s not found" (if (string-prefix-p "[[" (cdr e)) (cdr e)
                                                 (funcall refs (list (cdr e)))))))
           (and (or broken duplicates)
                (cons (org-truss--check-heading "Broken links")
                 (mapcar (lambda (b)
                           (org-truss--line
                            "   "
                            (propertize (format "[[%s]] ← %s" (org-truss--target (cdr b))
                                                (org-truss-section-label (car b)))
                                        'face 'org-truss-attention)
                            nil (list :type 'broken :pos (org-truss-section-pos (car b))
                                      :link (cdr b) :section (org-truss-section-pos (car b))
                                      :key (list 'broken (cdr b)))))
                         broken)))
           (and duplicates
                (list (org-truss--line "   "
                                       (propertize (mapconcat (lambda (id) (concat "#" id)) duplicates " · ")
                                                   'face 'org-truss-attention)
                                       (propertize "each the CUSTOM_ID of more than one member"
                                                   'face 'org-truss-dim)
                                       (list :key '(duplicates)))))
           (org-truss--check-group
            model "No grounds" (funcall in (mapcar #'list (plist-get checks :no-grounds)))
            (lambda (_) "no grounds"))
           (org-truss--check-group
            model "Weak grounds" (funcall in (plist-get checks :weak-grounds))
            (lambda (e) (format "%s has no grounds" (funcall refs (list (cdr e))))))
           (org-truss--check-group
            model "Missing roles" (funcall in (plist-get checks :gaps))
            (lambda (e) (mapconcat (lambda (gap)
                                     (let ((asking (org-truss--asking (car e) gap)))
                                       (format "%s%s%s" (org-truss-role-name (cadr gap))
                                               (if (> (cddr gap) 1) (format " ×%d" (cddr gap)) "")
                                               (if asking (format " (%s)" asking) ""))))
                                   (cdr e) ", ")))
           (org-truss--check-group
            model "No role" (funcall in (plist-get checks :no-role))
            (lambda (e) (format "plays no role of %s"
                                (org-truss-pattern-label (org-truss-cluster-pattern (cddr e) (cadr e))))))
           (org-truss--check-group
            model "Out of order" (funcall in (plist-get checks :out-of-order))
            (lambda (e) (format "below %s" (org-truss-cluster-label (cdr e))))))))
    (and lines (cons (org-truss--line "") lines))))

(defun org-truss--field-text (field)
  "Return the text of FIELD as lines, or nil.
One line; drawn whole, as many as it takes to break it to the room of the
middle."
  (let ((text (org-truss-field-notes field)))
    (and text (not (string-empty-p text))
         (mapcar (lambda (line) (propertize line 'face 'org-truss-dim))
                 (if org-truss--whole
                     (org-truss--fill text (- org-truss--middle-width 2))
                   (list (org-truss--one-line text)))))))

(defun org-truss--field-lines (model field part prefix inner)
  "Return board lines for FIELD of PART, the brief or the subject, of MODEL.
Its own line, PREFIX and the role it plays, with its text, and drawn
whole the rest of its text below, from INNER; then the members written
under it, so they can be gone to and placed from here.  A field that
plays none of the roles PART's breakdown names is named in the face of
what wants doing."
  (let* ((key (list (org-truss-part-name part) (org-truss-field-label field)))
         (text (org-truss--field-text field))
         (members (org-truss-field-children field))
         (fold (list 'field key))
         (folded (and members (org-truss--folded-p
                               fold (> (length members) org-truss-board-fold-limit))))
         (stray (org-truss--no-role-p field))
         (item (append (list :type 'brief :pos (org-truss-field-pos field)
                             :key (cons 'brief key) :field key)
                       (and stray
                            (list :why (format "Plays no role of %s; %s gives it one"
                                               (org-truss-patterns-label part)
                                               (substitute-command-keys "\\[org-truss-board-roles]"))))
                       (and members (list :fold fold :folded folded)))))
    (append (list (org-truss--line (concat prefix
                                           (if stray
                                               (propertize (org-truss-field-name field)
                                                           'face 'org-truss-attention)
                                             (org-truss-field-name field))
                                           (if folded (org-truss--fold-mark (length members)) ""))
                                   (car text) nil item))
            (org-truss--lines-under-heading inner (cdr text) nil nil item)
            (and (not folded)
                 (mapcan (lambda (m)
                           (org-truss--member-lines model m (concat inner "  ")
                                                    (list 'field key (org-truss-member-label m))))
                         members)))))

(defun org-truss--part-line (name gloss item &optional reader)
  "Return the line that opens the part NAME on the board.
GLOSS says what is done there; READER, what the document opens with."
  (org-truss--line (concat " " (propertize name 'face 'org-truss-section)
                           (propertize (concat "  " gloss) 'face 'org-truss-dim))
                   nil reader item))

(defun org-truss--part-lines (model part gloss)
  "Return the lines of PART of MODEL, the brief or the subject, on the board.
Its own line, with GLOSS, saying what is done there; the breakdown it
follows; its fields, as a tree; and a line for each role its breakdown
asks for and no field plays, on which a new field plays it."
  (let* ((name (org-truss-part-name part))
         (item (list :type 'brief :pos (org-truss-part-pos part)
                     :key (list 'brief name) :part name))
         (fields (org-truss-part-children part))
         (n (length fields))
         (i 0))
    (append
     (list (org-truss--part-line (capitalize (symbol-name name)) gloss item))
     (delq nil (list (org-truss--pattern-line part " " item)))
     (mapcan (lambda (field)
               (let ((last (= (setq i (1+ i)) n)))
                 (org-truss--field-lines model field part (if last " └ " " ├ ")
                                         (if last "   " " │ "))))
             fields)
     (mapcar (lambda (gap)
               (org-truss--line (concat "   " (org-truss--gap-text part gap)) nil nil
                                (append (list :gap (cons (car gap) (cadr gap))
                                              :key (append (plist-get item :key)
                                                           (list 'gap (car gap) (cadr gap))))
                                        item)))
             (cdr (assq part (plist-get org-truss--checks :gaps)))))))

(defun org-truss--structure-lines (model)
  "Return the structure's tree for MODEL, as the document tells it."
  (let ((root (org-truss-model-structure model))
        (org-truss--in-structure t))
    (if (null root)
        ;; A heading read alone makes no document, and is not missing one.
        (unless (with-current-buffer (org-truss-model-buffer model) (org-truss--root-pos))
          (list (org-truss--line (propertize " (no structure part)" 'face 'org-truss-attention))))
      (let ((item (list :type 'section :pos (org-truss-section-pos root) :root t
                        :label (org-truss-section-label root) :key '(section root)))
            (stem (if (org-truss-section-children root) " │ " "   ")))
        ;; The root's heading names the part, as the brief's and the members'
        ;; do, and is not in the document; the board's word stands for it.
        (append
         (let ((lead (org-truss--reader-lines (cons nil (cdr (org-truss-section-public root))))))
           (append
            (list (org-truss--part-line "Structure" "how it is told: sections, listing members"
                                        item (car lead)))
            (org-truss--lines-under-heading " " nil (org-truss-section-notes root) (cdr lead) item
                                    (org-truss--pattern-line root " " item) stem)))
         (org-truss--links-lines model root stem '(root))
         (let* ((children (org-truss-section-children root)) (n (length children)) (i 0))
           (mapcan (lambda (child)
                     (setq i (1+ i))
                     (org-truss--section-lines model child " " (= i n) '(root) root))
                   children))
         (org-truss--section-gap-lines root "   " item))))))

(defun org-truss--board-lines (model)
  "Return the board for MODEL as a list of lines.
Under the title come the four parts, in the order the work is done in:
the brief, what the document must satisfy; the subject, what was found;
the members, what is made of it; the structure, how it is told.  Each is
followed by what is left to do there."
  (let* ((org-truss--model model)
         (org-truss--uses (org-truss--member-uses model))
         (org-truss--placed (org-truss-told model))
         (checks (org-truss-checks model))
         (org-truss--checks checks)
         (brief (org-truss-model-brief model))
         (subject (org-truss-model-subject model)))
    (append (org-truss--head-lines model)
            (and brief
                 (append (list (org-truss--line ""))
                         (org-truss--part-lines model brief "what the document must satisfy")
                         (org-truss--check-lines model checks 'brief)))
            (and subject
                 (append (list (org-truss--line ""))
                         (org-truss--part-lines model subject "what was found")
                         (org-truss--check-lines model checks 'subject)))
            (org-truss--members-part model checks)
            (list (org-truss--line ""))
            (org-truss--structure-lines model)
            (org-truss--check-lines model checks 'structure))))

(defun org-truss--head-lines (model)
  "Return the head of the board for MODEL: the title."
  (let ((title (org-truss-model-title model))
        (pos (alist-get '(title) (org-truss-model-locations model) nil nil #'equal)))
    (list (org-truss--line
           (concat " Title" (if (buffer-modified-p (org-truss-model-buffer model))
                                (propertize "  unsaved" 'face 'org-truss-attention)
                              ""))
           (propertize (or title "") 'face 'org-truss-section)
           (and title (propertize title 'face 'org-truss-reader))
           (and pos (list :type 'brief :pos pos :key '(brief title)))))))

(defun org-truss--members-part (model checks)
  "Return the members part of the board for MODEL, then what is left to do.
That is what CHECKS finds of the members part's own."
  (let* ((root (with-current-buffer (org-truss-model-buffer model)
                 (org-with-wide-buffer (org-truss--root-pos))))
         (pos (or root
                  (with-current-buffer (org-truss-model-buffer model)
                    (org-with-wide-buffer (org-truss--part-pos "members"))))))
    (append
     (and pos
          (append
           (list (org-truss--line "")
                 (if root
                     (org-truss--part-line "Heading" "one heading, read as a truss file's members are"
                                           (list :type 'brief :pos pos :part 'members
                                                 :key '(brief (members))))
                   (org-truss--part-line "Members" "what is made of it"
                                         (list :type 'brief :pos pos :part 'members
                                               :key '(brief (members))))))
           (mapcan (lambda (m)
                     (org-truss--member-lines model m "   " (list 'member (org-truss-member-label m))))
                   (org-truss-model-members model))))
     (org-truss--check-lines model checks 'members))))

(defun org-truss--column (lines)
  "Return the column the middle starts at on LINES.
Two past the widest of the board's own words, with the id a line names a
member by, on a line that has any."
  (+ 2 (seq-reduce (lambda (widest line)
                     (if (plist-get line :middle)
                         (max widest (+ (string-width (plist-get line :left))
                                        (let ((id (plist-get line :id)))
                                          (if id (1+ (string-width id)) 0))))
                       widest))
                   lines 0)))

(defun org-truss--owner (key)
  "Return the key of the line that the line keyed KEY is drawn for.
The lines a heading's line takes below it -- the rest of its text, the
line naming its pattern, a line its words are broken onto -- are its own;
any other line is its own owner."
  (pcase (last key 2)
    (`(,(or 'text 'wrap) ,(pred integerp)) (butlast key 2))
    (`(,_ pattern) (butlast key))
    (_ key)))

(defun org-truss--groups (lines)
  "Return LINES as groups (KEY LINE...), a line with those it takes below it.
KEY is the owner of each, as `org-truss--owner' says."
  (let (groups)
    (dolist (line lines)
      (let ((key (org-truss--owner (plist-get (plist-get line :item) :key))))
        (if (and groups (equal key (caar groups)))
            (push line (cdar groups))
          (push (list key line) groups))))
    (nreverse (mapcar (lambda (group) (cons (car group) (nreverse (cdr group)))) groups))))

(defun org-truss--swap (lines other)
  "Return LINES, with each line `org-truss--wrapping' holds as OTHER draws it.
LINES and OTHER are the board drawn whole and on one line, one each,
so the same lines come in the same order in both; each takes the lines it
takes below it there."
  (let ((groups (org-truss--groups lines))
        (others (org-truss--groups other)))
    (if (/= (length groups) (length others))
        lines
      (cl-mapcan (lambda (group other)
                   (cdr (if (member (car group) org-truss--wrapping) other group)))
                 groups others))))

(defun org-truss--model-directory (model)
  "Return the directory the truss file of MODEL is in."
  (with-current-buffer (org-truss-model-buffer model)
    (if buffer-file-name (file-name-directory buffer-file-name) default-directory)))

(defun org-truss-board-text (model &optional entries width)
  "Return the board for MODEL as a string, every line whole when ENTRIES.
The lines `org-truss--wrapping' holds are drawn the other way.  The middle
starts one column for every line.  WIDTH is that of the window the board
is drawn for: right of that column, the middle and the right share it, and
a line drawn whole is broken to fit; see `org-truss-board-middle-width'
and `org-truss-board-right-width'."
  (let* ((plain (let ((org-truss--whole nil)) (org-truss--board-lines model)))
         ;; Where the middle starts does not depend on what is drawn whole,
         ;; so the drawing on one line each says.
         (column (org-truss--column plain))
         (room (and width (- width 1 column)))
         (org-truss--middle-width
          (cond (org-truss-board-middle-width)
                ;; Two of the middle's columns go to the gap before the
                ;; right, so each side gets the same room for words.
                (room (max 20 (/ (+ room 2) 2)))
                (t 40)))
         (org-truss--right-width
          (cond (org-truss-board-right-width)
                (room (max 20 (- room org-truss--middle-width)))
                (t 60)))
         (org-truss--middle-column column)
         (org-truss--base-directory (org-truss--model-directory model))
         (whole (and (or entries org-truss--wrapping)
                     (let ((org-truss--whole t))
                       (mapcan #'org-truss--whole-lines (org-truss--board-lines model)))))
         (lines (cond ((null org-truss--wrapping) (if entries whole plain))
                      (entries (org-truss--swap whole plain))
                      (t (org-truss--swap plain whole)))))
    (mapconcat (lambda (line) (org-truss--lay-out line column)) lines "")))

(provide 'org-truss-draw)

;;; org-truss-draw.el ends here

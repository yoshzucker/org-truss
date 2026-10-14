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
  "Face for assumptions and for claims that rest on one."
  :group 'org-truss)

(defface org-truss-attention '((t :inherit warning))
  "Face for what wants doing: bare members, open questions, gaps."
  :group 'org-truss)

(defface org-truss-reader '((t))
  "Face for what the reader sees as a heading, in the board's right column.
What the reader sees as body text takes `org-truss-dim', as the notes under
a heading do in the middle column."
  :group 'org-truss)

(defface org-truss-untold '((t :inherit org-truss-dim :slant italic))
  "Face for what the reader would see of a member the document does not tell.
In the subject and the members, the right of a member placed nowhere, nor
under one placed."
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
  '((ground-of . "⏚") (built-on . "⌂") (told-in . "▤"))
  "The marks of the lines that name the other end of a link, by what it is.
Each line is under a member and names another, or a section, and its mark
says what the member above is to it: `ground-of', the ground it stands on,
named in its TRUSS_GROUNDS; `built-on', standing on it, which the member
above names in its own; `told-in', listed in that section, where the
document tells it.  One character each, as wide as a letter where the
board is drawn, keeps the tree in line."
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
grounds, nor where it is used, nor what its pattern still asks for, nor,
for a member of the subject, its parts.  Elsewhere it brings all of them,
and its right is what the reader is told of it all the same.")

(defvar org-truss--uses nil
  "While a board is drawn, how each member is used, by the member.
\(SECTIONS . MEMBERS): the sections that list it, and the members it is a
ground of, each in the order of the file.")

(defvar org-truss--placed nil
  "While a board is drawn, the members the document tells.
Those its sections list, with what is nested under them; see
`org-truss-usage'.")

(defvar org-truss--order 'written
  "Where a board opens a member a section lists: `written' or `told'.
As written, where it is written, with what is nested under it, and the
structure lists it on one line.  As told, under the section, with all it
brings where it is written -- its uses, its grounds, its gaps -- and
where it is written it is one line.  Either can be unfolded where it is
one line; a member of the subject is always opened where it is written,
since the document tells only its own words.")

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

(defun org-truss--kind-word (model member)
  "Return the word the board uses for MEMBER's kind, with its face."
  (let* ((kind (org-truss-member-kind model member))
         (face (cond ((or (org-truss-hypothesis-p model member) (eq kind 'assumption)
                          (and (eq kind 'summary) (org-truss--rests-on-open-p model member nil)))
                      'org-truss-tentative)
                     ((or (memq kind '(bare question))
                          (and (eq kind 'objection) (org-truss-unanswered-p model member)))
                      'org-truss-attention))))
    (propertize (if (org-truss-hypothesis-p model member) "hypothesis" (symbol-name kind))
                'face face)))

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
or its label; `noexport' when the reader sees nothing of it.  Whom to
confirm it with, when the file says, follows the first line, or with entry
text, the last, on lines of its own."
  (let ((lines (if (org-truss-noexport-p member)
                   (list (propertize "noexport" 'face 'org-truss-dim))
                 (org-truss--reader-lines (org-truss-member-told member where wording))))
        (confirm (and (org-truss-member-confirm member)
                      (propertize (concat "confirm with " (org-truss-member-confirm member))
                                  'face 'org-truss-attention))))
    (cond ((null confirm) lines)
          (org-truss--whole
           (append lines (org-truss--break confirm org-truss--right-width)))
          (t (cons (string-join (delq nil (list (car lines) confirm)) "  ")
                   (cdr lines))))))

(defun org-truss--level-face (level)
  "Return the face Org gives the words of a heading at LEVEL.
As `org-get-level-face' works it out, for odd levels only and for faces
that cycle or stop at the last."
  (let ((n (if org-odd-levels-only (1+ (/ level 2)) level)))
    (if org-cycle-level-faces
        (nth (% (1- n) org-n-level-faces) org-level-faces)
      (nth (1- (min n org-n-level-faces)) org-level-faces))))

(defun org-truss--placeholder-p (cluster)
  "Non-nil when the board being drawn lists CLUSTER among the placeholders."
  (memq cluster (plist-get org-truss--checks :placeholders)))

(defun org-truss--placeholder-why ()
  "Return what the board says on a heading still called what its place is."
  (substitute-command-keys
   "Still called what its place in the pattern is called; \\[org-truss-board-rename] rewrites it"))

(defun org-truss--member-words (member)
  "Return MEMBER's heading as the board draws it: in the face the file gives
a heading of its level.  The board colours it itself, rather than copy the
file's, which is there only where the file has been shown.  A heading
still called what its place is called is in the face of what wants doing."
  (propertize (org-truss-member-label member)
              'face (if (org-truss--placeholder-p member)
                        'org-truss-attention
                      (org-truss--level-face (org-truss-member-level member)))))

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
  '((ground-of . "The member above is a ground of this one: this one stands on it, through its TRUSS_GROUNDS")
    (built-on . "The member above stands on this one, through its TRUSS_GROUNDS: this one is its ground")
    (told-in . "This section lists the member above: the document tells it here"))
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
Each section that lists it, by its roles and its heading, marked as where
it is told in, and then each member it is a ground of, by its kind and
its heading, marked as standing on it: the other end of a link, as the
line of a ground it stands on is of one.  In the structure, where it is
drawn under the section, the section goes without saying.  STEM starts
each; KEY is MEMBER's line's.  Each goes to what it names."
  (let ((use (and org-truss--uses (gethash member org-truss--uses)))
        (root (org-truss-model-structure model)))
    (mapcar
     (lambda (line) (append line (list :under stem :cut t)))
     (append
      (mapcar (lambda (section)
                (org-truss--line
                 (concat stem (org-truss--mark 'told-in)
                         (if (eq section root) "Structure" (org-truss--section-word section)))
                 (and (not (eq section root))
                      (propertize (org-truss-section-label section) 'face 'org-truss-dim))
                 nil
                 (list :type 'use :pos (org-truss-section-pos section)
                       :key (append key (list 'use (org-truss-section-pos section))))))
              (and (not org-truss--in-structure) (car use)))
      (mapcar (lambda (user)
                (org-truss--line
                 (concat stem (org-truss--mark 'ground-of) (org-truss--kind-word model user))
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

(defun org-truss--member-lines (model member indent key
                                      &optional link section marker wording)
  "Return board lines for MEMBER and what is nested under it.
INDENT starts each line: a string, or a cons (LINE . UNDER) for a member
nested under another, LINE starting its own line and UNDER the lines under
it, as `org-truss--branch' makes them.  The members nested under MEMBER
branch off right under it, as the sections of the structure do; its
pattern heads them, and its grounds go in further, as a section's links do.
KEY identifies the line across redraws.  LINK, the reference the
section's link makes, and SECTION are set when a section lists MEMBER, so
the line can be moved; WORDING, when that section tells it in words of
its own.  MARKER is how the reader sees it begin: its number or bullet
when it says how to do the member above it, and the aspect it covers when
that member has aspects.  A member still called what its place is called
has its heading in the face of what wants doing.

The right is what the document tells of it: what its telling pattern
tells it in where it comes, and, when the pattern closes with it again, a
line after what is under it.  Where it is opened, as `org-truss--order'
says, where it is used follows it, then the grounds it stands on, each
line marked as `org-truss-board-marks' says, and the places its pattern
asks for and it lacks; where it is not, it starts folded, to one line.  In the structure, `org-truss--in-structure',
only what the document tells comes with it besides: nothing under a
member of the subject.  Elsewhere its right is in the face of what is not
told while the document does not tell it, and empty under a member of the
subject, whose parts it never tells.  A member the file has below one its
parent's telling pattern tells after it is marked."
  (let* ((under (if (consp indent) (cdr indent) indent))
         (indent (if (consp indent) (car indent) indent))
         (in-structure org-truss--in-structure)
         (finding (org-truss-finding-p member))
         ;; A cluster always says what it is, written or not: with nothing
         ;; written, what is under it is its support, why › reasons.
         (patterned (or (org-truss-member-logic member) (org-truss-member-aspects member)
                        (org-truss-member-telling member) (org-truss-member-children member)))
         (roles (org-truss-member-roles member))
         (label (org-truss--label-lines (org-truss--member-words member)))
         ;; A marker opens the first line, and the lines after it are
         ;; indented as far, as a list item's are.
         (hang (if marker (string-width marker) 0))
         (marked (lambda (lines)
                   (if (and marker (car lines))
                       (cons (concat marker (car lines))
                             (mapcar (lambda (line)
                                       (if (string-empty-p line) line
                                         (concat (make-string hang ?\s) line)))
                                     (cdr lines)))
                     lines)))
         (first (org-truss-told-first-p member))
         (children (and (not (and in-structure finding)) (org-truss-member-children member)))
         (nested (length (mapcan #'org-truss--subtree children)))
         ;; It is opened in one place, by the order the board is drawn
         ;; in, and starts folded in the other; see `org-truss--order'.
         (elsewhere (if (eq org-truss--order 'told)
                        (and (not in-structure) (not finding)
                             (car (and org-truss--uses (gethash member org-truss--uses))))
                      (and in-structure link)))
         (folded (and (> nested 0) (org-truss--folded-p key (and elsewhere t))))
         (shown (and (not folded) children))
         ;; What it brings where it is written -- its uses, its grounds, its
         ;; gaps -- it brings where it is opened, as told under its section
         ;; but for a member of the subject, of which the document tells its
         ;; words alone; not where it is one line, nor a line it is drawn
         ;; on with nothing under it to fold.
         (full (and (not folded) (not elsewhere)
                    (or (not in-structure)
                        (and (eq org-truss--order 'told) (not finding)))))
         ;; A member told after what is under it is told, in the document,
         ;; below it: the right shows its words there, a line running
         ;; down to them from its own line.  Not a step or a part, whose
         ;; list item opens with it whatever its telling pattern; nor one
         ;; folded, whose words go on its own line.
         (last-told (and (not first) (not finding) (not folded)
                         (not (org-truss-noexport-p member))
                         (not (org-truss-how-child-p model member))))
         ;; Where it is written, the words the section placing it tells it
         ;; in are its all the same; what no section places is not told.
         (wording (or wording (and (not in-structure) (org-truss--told-wording member))))
         (untold (if (and (not in-structure) (not (memq member org-truss--placed)))
                     #'org-truss--untold
                   #'identity))
         (reader (cond ((and finding (org-truss-parent model member))
                        nil)
                       (last-told
                        (list (propertize "┐" 'face 'org-truss-branch)))
                       (t
                        ;; Folded, one told after what is under it has the
                        ;; words it is told in there on its own line.
                        (let ((org-truss--right-width (- org-truss--right-width hang))
                              (where (if (and folded (not first) (not finding)
                                              (not (org-truss-how-child-p model member)))
                                         'after
                                       'before)))
                          (funcall untold
                                   (funcall marked (org-truss--member-reader member wording where)))))))
         (answer (and last-told
                      (let ((org-truss--right-width (- org-truss--right-width hang 2)))
                        (funcall untold
                                 (funcall marked (org-truss--member-reader member wording 'after))))))
         (how (org-truss-how-children member))
         (n 0)
         ;; What comes between its pattern and the members branching off
         ;; below -- its notes, its grounds -- has the tree's line run past.
         (stem (concat under (if shown (propertize "│ " 'face 'org-truss-branch) "  ")))
         (item (append (list :type 'member :pos (org-truss-member-pos member)
                             :label (org-truss-member-label member)
                             :link link :section section :key key)
                       (and (> nested 0) (list :fold key :folded folded))))
         (above (cdr (assq member (plist-get org-truss--checks :out-of-order))))
         (late (and above
                    (format "%s tells it before %s, which is above it in the file"
                            (org-truss-pattern-name
                             (org-truss-member-telling (org-truss-parent model member)))
                            (org-truss-member-label above))))
         (why (string-join (delq nil (list late (and (org-truss--placeholder-p member)
                                                     (org-truss--placeholder-why))))
                           ". ")))
    (cons
     ;; Called from the structure, it names the member as the link does;
     ;; where it is written, by its id.  Nested under a member called
     ;; there, it is not called itself, and names nothing.
     (org-truss--with-id
      (org-truss--line
       (concat indent
               (if (org-truss-against-p member) "x " "")
               (org-truss--kind-word model member)
               (if folded (org-truss--fold-mark nested) "")
               (if roles
                   (propertize (format "  [%s]" (org-truss-role-names roles)) 'face 'org-truss-dim)
                 "")
               (if late (propertize " ⚠" 'face 'org-truss-attention) ""))
       (car label)
       (car reader)
       (if (string-empty-p why) item (append item (list :why why))))
      (and (or link (not in-structure)) (org-truss--id-text member link)))
     (org-truss--told-below
      (append
       (org-truss--lines-under-heading
        under (cdr label) (org-truss-member-notes member) (cdr reader) item
        (and patterned (not folded) (not (and in-structure finding))
             (org-truss--line
              (concat under
                      (propertize (format "(%s)"
                                          (string-join
                                           (cons (org-truss-pattern-label (org-truss-member-logic member))
                                                 (mapcar #'org-truss-pattern-label
                                                         (delq nil (list (org-truss-member-aspects member)
                                                                         (org-truss-member-telling member)))))
                                           ", "))
                                  'face 'org-truss-dim
                                  'help-echo (and (null (org-truss-member-logic member))
                                                  (substitute-command-keys
                                                   "No TRUSS_LOGIC is written, so what is under it is its support; \\[org-truss-board-pattern] writes one"))))
              nil nil (list :type 'member :pos (org-truss-member-pos member)
                            :key (append key '(pattern)))))
        stem)
       (and full (org-truss--use-lines model member stem key))
       (mapcar (lambda (ref)
                 (let ((ground (org-truss-member-by-ref model ref)))
                   (append
                    (org-truss--with-id
                     (org-truss--line
                      (concat stem (org-truss--mark 'built-on)
                              (if ground (org-truss--kind-word model ground)
                                (propertize "broken ground" 'face 'org-truss-attention)))
                      (propertize (if ground (org-truss-member-label ground)
                                    (format "[[%s]]" (org-truss--target ref)))
                                  'face 'org-truss-dim)
                      nil (list :type 'member :pos (org-truss-member-pos (or ground member))
                                :label (and ground (org-truss-member-label ground))
                                :claim (org-truss-member-pos member) :ground ref
                                :key (append key (list 'ground ref))))
                     (and ground (org-truss--id-text ground ref)))
                    (list :under stem :cut t))))
               (and full (org-truss-member-grounds member)))
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
                                            (and (not finding)
                                                 (not (org-truss-noexport-p child))
                                                 (if (memq child how)
                                                     (let ((marker (org-truss--list-marker
                                                                    member child (setq n (1+ n)))))
                                                       (concat (car marker) (cdr marker)))
                                                   (let ((label (org-truss--aspect-label member child)))
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
                  (concat under "  " (org-truss--gap-text gap))
                  nil nil (list :type 'member :pos (org-truss-member-pos member)
                                :gap (car gap)
                                :key (append key (list 'gap (car gap))))))
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
                       (propertize (concat indent "broken link") 'face 'org-truss-attention)
                       (propertize (format "[[%s]]" (org-truss--target ref)) 'face 'org-truss-attention)
                       nil (list :type 'broken :pos (org-truss-section-pos section)
                                 :link ref :section (org-truss-section-pos section) :key key))))))
          (org-truss-section-links section)))

(defun org-truss--misfit (roles pattern)
  "Say how a section answering ROLES fails to fit its parent's PATTERN, or nil.
PATTERN is a telling pattern.  A section fits when it fills exactly one of
its places.  A section that answers nothing is not judged here: its own
line says so."
  (let* ((places (mapcar #'car (org-truss-pattern-places pattern)))
         (hits (seq-filter (lambda (place) (memq place roles)) places)))
    (cond ((or (null roles) (null places) (= (length hits) 1)) nil)
          ((null hits) (format "no place for %s in %s"
                               (org-truss-role-names roles) (org-truss-pattern-name pattern)))
          (t (format "fits more than one place: %s"
                     (let ((names (mapcar #'org-truss-role-name hits)))
                       (concat (string-join (butlast names) ", ") " and " (car (last names)))))))))

(defun org-truss--pattern-line (cluster indent item)
  "Return the line naming the patterns CLUSTER follows, or nil if it follows none.
CLUSTER is a section, or the brief or the subject: its logic pattern, its
aspects, and its telling pattern, which give what is below their places.
It goes under CLUSTER's own line, at INDENT.  ITEM is CLUSTER's line's,
kept under a key of its own."
  (let ((label (org-truss-patterns-label cluster)))
    (and label
         (org-truss--line
          (concat indent (propertize (format "(%s)" label) 'face 'org-truss-dim))
          nil nil (plist-put (copy-sequence item) :key
                             (append (plist-get item :key) '(pattern)))))))

(defun org-truss--gap-text (gap)
  "Return how the board shows GAP, (ROLE . SHORT-BY): the role, and how many more."
  (propertize (format "%s —%s" (org-truss-role-name (car gap))
                      (if (> (cdr gap) 1) (format " ×%d" (cdr gap)) ""))
              'face 'org-truss-attention))

(defun org-truss--section-gap-lines (section indent item)
  "Return a line for each role SECTION's patterns ask for and nothing right
below answers, at INDENT; ITEM is SECTION's line's.  On one, a new section
answers that role."
  (mapcar (lambda (gap)
            (org-truss--line
             (concat indent (org-truss--gap-text gap))
             nil nil (append (list :gap (car gap)
                                   :key (append (plist-get item :key) (list 'gap (car gap))))
                             item)))
          (cdr (assq section (plist-get org-truss--checks :section-gaps)))))

(defun org-truss--section-word (section &optional parent)
  "Return the board's word for SECTION, on the left of its line: its roles.
With none, `no role' in the face of what wants doing when the patterns of
PARENT, the section above it, name places to fill; else `section'."
  (let ((roles (org-truss-section-roles section)))
    (cond (roles (org-truss-role-names roles))
          ((and parent (org-truss-named-roles parent))
           (propertize "no role" 'face 'org-truss-attention))
          (t "section"))))

(defun org-truss--section-lines (model section prefix last path parent)
  "Return board lines for SECTION and the sections below it.
PREFIX draws the tree to the left; LAST says SECTION ends its siblings.
PATH is the labels from the root, which identifies the line across redraws.
PARENT is the section above.  A section that does not fit its telling
pattern, or that comes below one the pattern tells after, is marked."
  (let* ((path (append path (list (org-truss-section-label section))))
         (inner (concat prefix (if last "  " "│ ")))
         (children (org-truss-section-children section))
         ;; Its notes and links have the line to the sections below run past.
         (stem (concat inner (if children "│ " "  ")))
         (roles (org-truss-section-roles section))
         (parent-pattern (org-truss-section-telling parent))
         (misfit (and parent-pattern (org-truss--misfit roles parent-pattern)))
         (above (cdr (assq section (plist-get org-truss--checks :out-of-order))))
         (late (and above
                    (format "%s tells it before %s, which is above it in the file"
                            (org-truss-pattern-name parent-pattern)
                            (org-truss-section-label above))))
         (misfit (if (and misfit late) (concat misfit ". " late) (or misfit late)))
         (public (org-truss-section-public section))
         (title (org-truss-section-title section))
         (unnamed (and (org-truss--placeholder-p section)
                       (format "The reader is given %s, the pattern's name for this place; %s names it for them"
                               title (substitute-command-keys "\\[org-truss-board-rename]"))))
         (label (org-truss--label-lines
                 (propertize (org-truss-section-label section) 'face 'org-truss-section)))
         (reader (org-truss--reader-lines (cons title (cdr public))))
         (reader (if unnamed
                     (cons (propertize (car reader) 'face 'org-truss-attention) (cdr reader))
                   reader))
         (item (list :type 'section :pos (org-truss-section-pos section)
                     :label (org-truss-section-label section)
                     :key (list 'section path))))
    (append
     (list (org-truss--line (concat prefix (if last "└ " "├ ")
                                    (org-truss--section-word section parent)
                                    (if misfit (propertize " ⚠" 'face 'org-truss-attention) ""))
                            (car label)
                            (car reader)
                            (append item (list :why (and (or misfit unnamed)
                                                               (string-join (delq nil (list misfit unnamed))
                                                                            ". "))))))
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

(defun org-truss--list-lines (model heading members kind &optional right)
  "Return a HEADING line and one line per member of MEMBERS, keyed by KIND.
RIGHT, given a member, returns what goes on the right of its line; by
default what the reader sees of it.  HEADING names a check, and what the
check finds is shown when the mouse is on it."
  (when members
    (cons (org-truss--check-heading heading)
          (mapcar (lambda (m)
                    (org-truss--with-id
                     (org-truss--line
                      (concat "   " (org-truss--kind-word model m))
                      (org-truss--member-words m)
                      (if right
                          (funcall right m)
                        (car (let ((org-truss--whole nil)) (org-truss--member-reader m))))
                      (list :type 'member :pos (org-truss-member-pos m)
                            :label (org-truss-member-label m)
                            :key (list kind (org-truss-member-label m))))
                     (org-truss--id-text m)))
                  members))))

(defun org-truss--section-list-lines (heading sections kind &optional right)
  "Return a HEADING line and one line per section of SECTIONS, keyed by KIND.
Each with its roles on the left and its heading in the middle.  RIGHT,
given a section, returns what goes on the right of its line; by default
the title the reader is given.  HEADING names a check, as for
`org-truss--list-lines'."
  (when sections
    (cons (org-truss--check-heading heading)
          (mapcar (lambda (s)
                    (org-truss--line
                     (concat "   " (org-truss--section-word s))
                     (org-truss-section-label s)
                     (if right
                         (funcall right s)
                       (propertize (org-truss-section-title s) 'face 'org-truss-reader))
                     (list :type 'section :pos (org-truss-section-pos s)
                           :label (org-truss-section-label s)
                           :key (list kind (org-truss-section-label s)))))
                  sections))))

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
Its own line, PREFIX and the places it fills, with its text, and drawn
whole the rest of its text below, from INNER; then the members written
under it, so they can be gone to and placed from here.  A field that
fills none of the places PART's aspects name is named in the face of what
wants doing."
  (let* ((key (list (org-truss-part-name part) (org-truss-field-label field)))
         (text (org-truss--field-text field))
         (members (org-truss-field-children field))
         (fold (list 'field key))
         (folded (and members (org-truss--folded-p
                               fold (> (length members) org-truss-board-fold-limit))))
         (stray (memq field (org-truss-no-aspect part)))
         (item (append (list :type 'brief :pos (org-truss-field-pos field)
                             :key (cons 'brief key) :field key)
                       (and stray
                            (list :why (format "Fills no place of %s; %s gives it one"
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
Its own line, with GLOSS, saying what is done there; the patterns it
follows; its fields, as a tree; and a line for each place its pattern
asks for and no field fills, on which a new field fills it."
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
               (org-truss--line (concat "   " (org-truss--gap-text gap)) nil nil
                                (append (list :gap (car gap)
                                              :key (append (plist-get item :key) (list 'gap (car gap))))
                                        item)))
             (cdr (assq part (plist-get org-truss--checks :part-gaps)))))))

(defun org-truss--structure-lines (model)
  "Return the structure's tree for MODEL, as the document tells it."
  (let ((root (org-truss-model-structure model))
        (org-truss--in-structure t))
    (if (null root)
        (list (org-truss--line (propertize " (no structure part)" 'face 'org-truss-attention)))
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
Under the title and the brief come the three parts the work is done in, in
the order it is done: the subject, what was found -- facts, summed up in
clusters; the members, what is made of it -- interpretations of the facts,
and decisions; the structure, how it is told.  Each is followed by what is
left to do there."
  (let* ((org-truss--model model)
         (org-truss--uses (org-truss--member-uses model))
         (org-truss--placed (car (org-truss-usage model)))
         (checks (org-truss-checks model))
         (org-truss--checks checks))
    (append (org-truss--head-lines model)
            (org-truss--subject-part model checks)
            (org-truss--members-part model checks)
            (org-truss--structure-part model checks))))

(defun org-truss--head-lines (model)
  "Return the head of the board for MODEL: the title, then the brief."
  (let ((title (org-truss-model-title model))
        (pos (alist-get '(title) (org-truss-model-locations model) nil nil #'equal))
        (brief (org-truss-model-brief model)))
    (cons (org-truss--line
           (concat " Title" (if (buffer-modified-p (org-truss-model-buffer model))
                                (propertize "  unsaved" 'face 'org-truss-attention)
                              ""))
           (propertize (or title "") 'face 'org-truss-section)
           (and title (propertize title 'face 'org-truss-reader))
           (and pos (list :type 'brief :pos pos :key '(brief title))))
          (and brief
               (cons (org-truss--line "")
                     (org-truss--part-lines model brief "what the document must satisfy"))))))

(defun org-truss--misplaced-lines (model misplaced kind)
  "Return the lines of the check Misplaced for MISPLACED, keyed by KIND.
MISPLACED is (MEMBER . WHY); why goes on the right of each line."
  (org-truss--list-lines model "Misplaced" (mapcar #'car misplaced) kind
                         (lambda (m) (propertize (cdr (assq m misplaced)) 'face 'org-truss-attention))))

(defun org-truss--subject-part (model checks)
  "Return the subject's part of the board for MODEL, then what is left to do.
That is what CHECKS finds of the subject and its findings -- the fields
its pattern asks for, among the gaps -- and the constraints unmet."
  (let* ((findings (lambda (ms) (seq-filter #'org-truss-finding-p ms)))
         (subject (org-truss-model-subject model))
         (part-gaps (cdr (assq subject (plist-get checks :part-gaps))))
         (gaps (org-truss--list-lines model "Pattern gaps"
                                      (funcall findings (mapcar #'car (plist-get checks :member-gaps)))
                                      'subject-gaps)))
    (append
     (and subject
          (cons (org-truss--line "")
                (org-truss--part-lines model subject "what was found: facts, summed up in clusters")))
     (org-truss--list-lines model "Unmet constraints" (plist-get checks :unmet) 'unmet)
     (org-truss--list-lines model "No source" (funcall findings (plist-get checks :bare)) 'unsourced)
     (org-truss--list-lines model "Open questions" (funcall findings (plist-get checks :questions))
                            'subject-questions)
     (org-truss--list-lines model "Assumptions" (funcall findings (plist-get checks :assumptions))
                            'subject-assumptions)
     ;; The subject's own gaps head the list, with the pattern that asks,
     ;; as the structure's head its own.
     (and (or part-gaps gaps)
          (cons (org-truss--check-heading "Pattern gaps")
                (append
                 (and part-gaps
                      (list (org-truss--line
                             "   Subject"
                             (propertize (org-truss-patterns-label subject) 'face 'org-truss-dim)
                             (propertize (org-truss-role-names (mapcar #'car part-gaps))
                                         'face 'org-truss-attention)
                             (list :type 'brief :pos (org-truss-part-pos subject) :part 'subject
                                   :key '(subject-gaps part)))))
                 (cdr gaps))))
     (org-truss--list-lines model "No aspect" (funcall findings (plist-get checks :no-aspect))
                            'subject-no-aspect)
     (org-truss--list-lines model "Placeholders"
                            (funcall findings (seq-filter #'org-truss-member-p
                                                          (plist-get checks :placeholders)))
                            'subject-placeholders)
     (org-truss--misplaced-lines model (seq-filter (lambda (c) (org-truss-finding-p (car c)))
                                                   (plist-get checks :misplaced))
                                 'subject-misplaced))))

(defun org-truss--members-part (model checks)
  "Return the members part of the board for MODEL, then what is left to do.
That is what CHECKS finds of the members part's own, not the findings."
  (let ((pos (with-current-buffer (org-truss-model-buffer model)
               (org-with-wide-buffer (org-truss--part-pos "members"))))
        (argued (lambda (ms) (seq-remove #'org-truss-finding-p ms)))
        (broken (plist-get checks :broken-grounds)))
    (append
     (and pos
          (append
           (list (org-truss--line "")
                 (org-truss--part-line "Members" "what is made of it: interpretations and decisions"
                                       (list :type 'brief :pos pos :part 'members
                                             :key '(brief (members)))))
           (mapcan (lambda (m)
                     (org-truss--member-lines model m "   " (list 'member (org-truss-member-label m))))
                   (org-truss-model-members model))))
     (org-truss--list-lines model "Not placed" (plist-get checks :not-placed) 'not-placed)
     (org-truss--list-lines model "Only as grounds" (plist-get checks :grounds-only) 'grounds)
     (org-truss--list-lines model "Bare (no source, no support)"
                            (funcall argued (plist-get checks :bare)) 'bare)
     (org-truss--list-lines model "Open questions" (funcall argued (plist-get checks :questions))
                            'questions)
     (org-truss--list-lines model "Assumptions" (funcall argued (plist-get checks :assumptions))
                            'assumptions)
     (org-truss--list-lines model "Unanswered objections" (plist-get checks :unanswered) 'unanswered)
     (org-truss--list-lines model "Pattern gaps"
                            (funcall argued (mapcar #'car (plist-get checks :member-gaps)))
                            'member-gaps)
     (org-truss--list-lines model "No aspect" (funcall argued (plist-get checks :no-aspect))
                            'no-aspect)
     (let ((late (seq-filter (lambda (o) (org-truss-member-p (car o)))
                             (plist-get checks :out-of-order))))
       (org-truss--list-lines model "Out of order" (mapcar #'car late) 'out-of-order
                              (lambda (m)
                                (propertize (format "below %s" (org-truss-member-label
                                                                (cdr (assq m late))))
                                            'face 'org-truss-attention))))
     (org-truss--list-lines model "Placeholders"
                            (funcall argued (seq-filter #'org-truss-member-p
                                                        (plist-get checks :placeholders)))
                            'placeholders)
     (org-truss--misplaced-lines model (seq-remove (lambda (c) (org-truss-finding-p (car c)))
                                                   (plist-get checks :misplaced))
                                 'misplaced)
     (org-truss--list-lines model "Broken grounds" (seq-uniq (mapcar #'car broken)) 'broken-grounds
                            (lambda (m)
                              (propertize (mapconcat (lambda (b) (format "[[%s]]" (org-truss--target (cdr b))))
                                                     (seq-filter (lambda (b) (eq (car b) m)) broken)
                                                     " ")
                                          'face 'org-truss-attention))))))

(defun org-truss--structure-part (model checks)
  "Return the structure's part of the board for MODEL, then what is left to do.
That is what CHECKS finds of the sections: gaps, sections out of order,
still called what their place is called, or empty, links to no member,
and ids more than one member has, which break links."
  (let* ((gaps (plist-get checks :section-gaps))
         (late (seq-filter (lambda (o) (org-truss-section-p (car o)))
                           (plist-get checks :out-of-order)))
         (placeholders (seq-filter #'org-truss-section-p (plist-get checks :placeholders)))
         (empty (plist-get checks :empty-sections))
         (broken (plist-get checks :broken-links))
         (duplicates (plist-get checks :duplicates)))
    (append
     (list (org-truss--line ""))
     (org-truss--structure-lines model)
     (and (or gaps late placeholders empty broken duplicates)
          (list (org-truss--line "")))
     (and gaps
          (cons (org-truss--check-heading "Pattern gaps")
                (mapcar (lambda (g)
                          (let ((root (eq (car g) (org-truss-model-structure model))))
                            (org-truss--line
                             (concat "   " (if root "Structure" (org-truss--section-word (car g))))
                             ;; The Structure's heading is not the document's; the
                             ;; pattern that asks is named in its place.
                             (if root
                                 (propertize (or (org-truss-patterns-label (car g))
                                                 "an assumption is in use")
                                             'face 'org-truss-dim)
                               (org-truss-section-label (car g)))
                             (propertize (org-truss-role-names (mapcar #'car (cdr g)))
                                         'face 'org-truss-attention)
                             (list :type 'section :pos (org-truss-section-pos (car g))
                                   :label (org-truss-section-label (car g)) :root root
                                   :key (list 'section-gaps
                                              (if root 'root (org-truss-section-label (car g))))))))
                        gaps)))
     (org-truss--section-list-lines
      "Out of order" (mapcar #'car late) 'section-out-of-order
      (lambda (s)
        (propertize (format "below %s" (org-truss-section-label (cdr (assq s late))))
                    'face 'org-truss-attention)))
     (org-truss--section-list-lines
      "Placeholders" placeholders 'section-placeholders
      (lambda (s) (propertize (org-truss-section-title s) 'face 'org-truss-attention)))
     (org-truss--section-list-lines "Empty sections" empty 'empty-sections)
     (and broken
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
          (list (org-truss--line (propertize " Duplicate ids" 'face 'org-truss-section
                                             'help-echo (org-truss-check-about "Duplicate ids"))
                                 (propertize (mapconcat (lambda (id) (concat "#" id)) duplicates " · ")
                                             'face 'org-truss-attention)))))))

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

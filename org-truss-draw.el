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
  "Face for a title the reader sees, in the board's right column.
A section's heading in the document, or a member's title, in bold there.
What the reader sees as body text takes `org-truss-dim', as the notes under
a heading do in the middle column."
  :group 'org-truss)

(defface org-truss-untold '((t :inherit org-truss-dim :slant italic))
  "Face for what the reader would see of a member the document does not tell.
The right of a member placed nowhere, nor under one placed."
  :group 'org-truss)

(defface org-truss-branch '((t :inherit org-truss-dim))
  "Face for the tree that joins a member to the members nested under it.
The tree of the sections keeps the default face, so the two trees read
apart where they meet."
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
`ground', what the member above stands on -- a member or a source its
text links to, the words it quotes -- drawn below it; `built', a member standing
on the member above, which names it in its own -- drawn below it all the
same, so the mark points up; `section', a heading whose link tells the
member above, where the document tells it; and `item', a member the
heading above tells by its link, [[truss-include:m7]].  A line with no
mark is written there.  One character each, as wide as a
letter where the board is drawn, keeps the tree in line."
  :type '(alist :key-type symbol :value-type string)
  :group 'org-truss)

(defcustom org-truss-board-fold-limit nil
  "How many headings right under a heading the board shows before folding it.
A heading holding more -- members, sections, members its links tell --
starts folded, as one line that says how many it hides;
\\<org-truss-board-mode-map>\\[org-truss-board-cycle] unfolds it.  Nil, as
it is at first, starts the board open, each line on one line; 0 starts
every one folded, as an Org file starts in overview."
  :type '(choice (const :tag "Start open" nil) integer)
  :group 'org-truss)

(defun org-truss--over-limit-p (n)
  "Non-nil when N headings are more than `org-truss-board-fold-limit'."
  (and org-truss-board-fold-limit (> n org-truss-board-fold-limit)))

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
\(TELLERS . USERS): the headings whose links tell it, and those it is a
ground of, each in the order of the file.")

(defvar org-truss--placed nil
  "While a board is drawn, the members the document tells.
Those its sections tell, with what is nested under them and what they
tell in turn; see `org-truss-told'.")

(defvar org-truss--drawing nil
  "While a member is drawn, it and the members it is drawn under or told by.
One among them drawn again would be drawn without end.")

(defvar org-truss--order 'written
  "Where a board opens a member a section lists: `written' or `told'.
As written, where it is written, with what is nested under it, and the
structure lists it on one line.  As told, under the section, with all it
brings where it is written -- its uses, its grounds, its gaps -- and
where it is written it is one line.  Either can be unfolded where it is
one line.")

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
  "Return how the board names MEMBER, any heading, by its CUSTOM_ID, or nil.
REF, when the line calls it -- a link that tells it, a ground -- as
[[#m9]]; else as anything points to it, #m9, where it is written."
  (cond (ref (format "[[%s]]" (org-truss--target ref)))
        ((org-truss-cluster-id member) (concat "#" (org-truss-cluster-id member)))))

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

(defun org-truss--role-word (model cluster)
  "Return the board's word for CLUSTER of MODEL, on the left of its line.
The roles it plays in the patterns of the heading above, or `member' or
`section' when it plays none; then [no role] when it plays none of a
pattern above it, [assumed] when it is tagged :assumption:, and [no
grounds] when it must have grounds and lacks them, each in its face."
  (concat (or (org-truss--role-names cluster)
              (if (org-truss-section-p cluster) "section" "member"))
          (if (org-truss--no-role-p cluster) (propertize " [no role]" 'face 'org-truss-attention) "")
          (if (org-truss-assumption-p cluster) (propertize " [assumed]" 'face 'org-truss-tentative) "")
          (if (org-truss-missing-grounds model cluster)
              (propertize " [no grounds]" 'face 'org-truss-attention)
            "")))

(defun org-truss--link-text (text)
  "Return TEXT with each link read as its description, or else its target.
A link to a file without one reads as the file's name, and one to a
member, or telling one, as the member's heading."
  (replace-regexp-in-string
   "\\[\\[\\*?\\([^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]"
   (lambda (link)
     (let ((target (match-string 1 link)))
       (or (match-string 2 link)
           (save-match-data
             (and (string-match "\\`\\(?:file:\\|\\.\\.?/\\)\\([^:]+\\)" target)
                  (file-name-nondirectory (org-link-unescape (match-string 1 target)))))
           (let ((member (and org-truss--model
                              (org-truss-heading-by-ref
                               org-truss--model
                               (org-truss--ref (string-remove-prefix
                                                (concat org-truss-include-type ":") target))))))
             (and member (org-truss-cluster-label member)))
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

(defun org-truss--fill (text width &optional as-written)
  "Return TEXT as lines no wider than WIDTH, as it reads.
A paragraph of prose is joined and broken again.  A table, a block or a list
keeps its lines; a table's are cut where they run over.  Links read as their
descriptions, or, AS-WRITTEN, stay links, and a blank line stays between
paragraphs.  A picture linked
on a line of its own is drawn, where the board can show one, on the lines
it takes; see `org-truss--picture-lines'."
  (let ((read (if as-written #'identity #'org-truss--link-text))
        out)
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
                                          (let ((l (funcall read l)))
                                            (if (string-match-p "\\`[ \t]*|" l)
                                                (list (truncate-string-to-width l width))
                                              (org-truss--break l width))))))
                                  lines)
                        (org-truss--break (org-truss--one-line (funcall read para))
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

(defun org-truss--member-reader (member)
  "Return what the reader sees of MEMBER as lines, the first for its own line.
What `org-truss-member-told' says it is told in: its public block, or its
label; `noexport' when the reader sees nothing of it."
  (if (org-truss-noexport-p member)
      (list (propertize "noexport" 'face 'org-truss-dim))
    (org-truss--reader-lines (org-truss-member-told member))))

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

(defconst org-truss--link-line-re
  "^[ \t]*\\(?:[-+] \\)?\\[\\[[^]\n]+\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*\\(?:\n\\|\\'\\)"
  "A line holding nothing but a link, as a list item or not.")

(defun org-truss--notes-shown (notes)
  "Return NOTES without its quotations and the lines holding nothing but a link.
Each is a ground, words quoted or a member or a source the heading stands
on, which the board draws on a line of its own, marked; it would be drawn
twice."
  (when notes
    (dolist (block (reverse (org-truss--quote-blocks notes)))
      (setq notes (concat (substring notes 0 (car block)) (substring notes (cadr block)))))
    (string-trim (replace-regexp-in-string org-truss--link-line-re "" notes))))

(defun org-truss--lines-under-heading (left more notes below item &optional head stem)
  "Return the lines under a heading's own line on the board.
HEAD, if any, is the line that says how what is under the heading is
arranged.  Drawn whole, MORE, the rest of the heading's own words, and
then NOTES, what is written under the heading and stays in the file, go in
the middle, its links as written, since the lines below draw what they
point to; BELOW, the rest of what the reader sees, on the right.  LEFT
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
                          (org-truss--fill (or notes "") (- org-truss--middle-width 2) t)))
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
  '((ground . "Its grounds: what the member above stands on, linked in its text")
    (built . "Built on it: this member stands on the member above, which its text links to")
    (section . "Told here: a link in this heading tells the member above, and the document tells it here")
    (item . "Told by the heading above: its link tells this member, [[truss-include:id]], and the document tells it here"))
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
Each heading whose link tells it, by its roles and its heading, marked as
telling it, and then each heading it is a ground of, by its roles and its
heading, marked as built on it: the other end of a link, as the line of a
ground it stands on is of one.  In the structure, where it is drawn under
the heading that tells it, that goes without saying.  STEM starts each;
KEY is MEMBER's line's.  Each goes to what it names."
  (let ((use (and org-truss--uses (gethash member org-truss--uses)))
        (root (org-truss-model-structure model)))
    (mapcar
     (lambda (line) (append line (list :under stem :cut t)))
     (append
      (mapcar (lambda (teller)
                (org-truss--line
                 (concat stem (org-truss--mark 'section)
                         (if (eq teller root) "Structure" (org-truss--role-word model teller)))
                 (and (not (eq teller root))
                      (propertize (org-truss-cluster-label teller) 'face 'org-truss-dim))
                 nil
                 (list :type 'use :pos (org-truss-cluster-pos teller)
                       :key (append key (list 'use (org-truss-cluster-pos teller))))))
              (and (not org-truss--in-structure) (car use)))
      (mapcar (lambda (user)
                (org-truss--line
                 (concat stem (org-truss--mark 'built) (org-truss--role-word model user))
                 (propertize (org-truss-cluster-label user) 'face 'org-truss-dim)
                 nil
                 (list :type 'use :pos (org-truss-cluster-pos user)
                       :key (append key (list 'use (org-truss-cluster-pos user))))))
              (cdr use))))))

(defun org-truss--untold (lines)
  "Return LINES, what the reader would see, in the face of what is not told."
  (mapcar (lambda (line) (and line (propertize line 'face 'org-truss-untold))) lines))

(defun org-truss--told-links (cluster)
  "Return the references of the links CLUSTER tells members by, each once.
Not those it stands on, `org-truss-standing-includes': the board draws a
link as what it is to the heading, and those are its grounds."
  (seq-difference (seq-uniq (org-truss-cluster-includes cluster))
                  (org-truss-standing-includes cluster)))

(defun org-truss--member-uses (model)
  "Return how each member of MODEL is used, as `org-truss--uses' keeps it.
A link a heading stands on is a ground of it, though it tells it too; see
`org-truss-standing-includes'."
  (let ((uses (make-hash-table :test #'eq))
        (cell (lambda (m uses) (or (gethash m uses) (puthash m (cons nil nil) uses)))))
    (dolist (c (org-truss-clusters model))
      (dolist (ref (org-truss--told-links c))
        (let ((m (org-truss-heading-by-ref model ref)))
          (when m
            (let ((use (funcall cell m uses)))
              (setcar use (append (car use) (list c))))))))
    (dolist (c (org-truss-clusters model))
      (dolist (ref (org-truss-cluster-refs c))
        (let ((ground (org-truss-heading-by-ref model ref)))
          (when ground
            (let ((use (funcall cell ground uses)))
              (setcdr use (append (cdr use) (list c))))))))
    uses))

(defun org-truss--branch (indent last)
  "Return how the lines of a member nested under another start.
INDENT starts the other's lines.  A cons (LINE . UNDER) for
`org-truss--member-lines': LINE branches off to the member, and UNDER
carries the tree down past it to the next, unless the member is the LAST."
  (cons (concat indent (propertize (if last "└ " "├ ") 'face 'org-truss-branch))
        (concat indent (propertize (if last "  " "│ ") 'face 'org-truss-branch))))

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

(defun org-truss--grounds-lines (model cluster stem key)
  "Return a line for each thing CLUSTER of MODEL stands on, below it.
The members its text links to, each once, said to be broken when it is
no member, and to have no grounds when it does not hold, each called as
its link is written, [[#m7]] or [[truss-include:m7]]; then the words
it quotes, each quotation, and below them the sources its text links to,
each once, as the words are read from the source; a link among them that
points to nothing said not to be found.  Each keeps the links to sources
it opens, as :links: a source's own, and a quotation's, or else the first
the text cites.
STEM starts each; KEY is CLUSTER's line's."
  (let* ((pos (org-truss-cluster-pos cluster))
         (missing (mapcar #'cdr (seq-filter (lambda (b) (eq (car b) cluster))
                                            (plist-get org-truss--checks :broken-sources))))
         (found-p (lambda (text) (not (seq-some (lambda (link) (string-search link text)) missing))))
         (member-line
          (lambda (ref word)
            (let ((ground (org-truss-heading-by-ref model ref)))
              (org-truss--ground-line
               stem (append key (list 'ground ref))
               (cond ((null ground) (propertize (concat "broken " word) 'face 'org-truss-attention))
                     ((org-truss-holds-p ground) word)
                     (t (concat word (propertize " [no grounds]" 'face 'org-truss-attention))))
               (if ground (org-truss-cluster-label ground) (format "[[%s]]" (org-truss--target ref)))
               (list :type (if (org-truss-section-p ground) 'section 'member)
                     :pos (if ground (org-truss-cluster-pos ground) pos)
                     :label (and ground (org-truss-cluster-label ground))
                     :claim pos :ground ref)
               ;; Called as the link is written: one that tells it as well
               ;; says so, wherever in the heading it stands.
               (and ground (if (member ref (org-truss-standing-includes cluster))
                               (org-truss--include-link ref)
                             (org-truss--id-text ground ref))))))))
    (append
     (mapcar (lambda (ref) (funcall member-line ref "ground"))
             (org-truss-cluster-refs cluster))
     (mapcar (lambda (source)
               (org-truss--ground-line stem (append key (list 'source (car source)))
                                       (concat (symbol-name (car source))
                                               (if (funcall found-p (cdr source)) ""
                                                 (propertize " [not found]" 'face 'org-truss-attention)))
                                       (org-truss--one-line (org-truss--link-text (cdr source)))
                                       (list :type 'member :pos pos
                                             :links (if (eq (car source) 'source)
                                                        (list (cdr source))
                                                      (or (org-truss--source-links-in (cdr source))
                                                          (ensure-list (org-truss-cluster-cited cluster)))))))
             (append (mapcar (lambda (words) (cons 'quote words))
                             (org-truss-cluster-quoted cluster))
                     (mapcar (lambda (link) (cons 'source link))
                             (seq-uniq (org-truss-cluster-source-links cluster))))))))

(defun org-truss--member-lines (model member indent key
                                      &optional link holder marker)
  "Return board lines for MEMBER and what is nested under it.
INDENT starts each line: a string, or a cons (LINE . UNDER) for a member
nested under another, LINE starting its own line and UNDER the lines under
it, as `org-truss--branch' makes them.  The members nested under MEMBER
branch off right under it, as the sections of the structure do; its
patterns head them, and its grounds go in further, as a section's links do.
KEY identifies the line across redraws.  LINK, the reference of the link
that tells MEMBER, and HOLDER, the position of the heading it is in, are
set when MEMBER is drawn there, so the line can be moved.  MARKER is how
the reader sees it begin: its number or bullet when it is a part of the
member above's breakdown, written out as a list, and the role it plays
when that breakdown labels its parts.  The members MEMBER's own links
tell are drawn below its grounds, as a section's are; one drawn under
itself is drawn as one line, marked, since it would never end.

The right is what the document tells of it, which comes before what is
under it.  Where it is opened, as `org-truss--order'
says, where it is used follows it, then what it stands on, each line
marked as `org-truss-board-marks' says, and the roles its patterns ask for
and it lacks; where it is not, it starts folded, to one line.  In the
structure, `org-truss--in-structure', only what the document tells comes
with it besides.  Elsewhere its right is in the face of what is not told
while the document does not tell it.  A member the file has below one its
parent's telling pattern tells after it is marked."
  (let ((looping (memq member org-truss--drawing))
        (org-truss--drawing (cons member org-truss--drawing)))
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
         (up (org-truss-parent model member))
         (children (org-truss-member-children member))
         (includes (org-truss--told-links member))
         (nested (+ (length (mapcan #'org-truss--subtree children)) (length includes)))
         ;; It is opened in one place, by the order the board is drawn
         ;; in, and starts folded in the other: as written, where it is
         ;; written; as told, where a link tells it.  See `org-truss--order'.
         (elsewhere (if (eq org-truss--order 'told)
                        (and (not link) (not in-structure)
                             (car (and org-truss--uses (gethash member org-truss--uses))))
                      (and link t)))
         (folded (or (and looping (> nested 0))
                     (and (> nested 0)
                          (org-truss--folded-p key (or (and elsewhere t)
                                                       (org-truss--over-limit-p
                                                        (+ (length children) (length includes))))))))
         (shown (and (not folded) children))
         ;; What it brings where it is written -- its uses, its grounds, its
         ;; gaps -- it brings where it is opened; not where it is one line.
         (full (and (not folded) (not elsewhere)
                    (or (not in-structure) (eq org-truss--order 'told))))
         ;; What the document does not tell is drawn so.
         (untold (if (and (not in-structure) (not (memq member org-truss--placed)))
                     #'org-truss--untold
                   #'identity))
         (reader (let ((org-truss--right-width (- org-truss--right-width hang)))
                   (funcall untold (funcall marked (org-truss--member-reader member)))))
         (as-list (org-truss-list-form member))
         (n 0)
         ;; What comes between its patterns and the members branching off
         ;; below -- its notes, its grounds -- has the tree's line run past.
         (stem (concat under (if shown (propertize "│ " 'face 'org-truss-branch) "  ")))
         (item (append (list :type 'member :pos (org-truss-member-pos member)
                             :label (org-truss-member-label member)
                             :link link :holder holder :key key)
                       (and (> nested 0) (not looping) (list :fold key :folded folded))))
         (above (cdr (assq member (plist-get org-truss--checks :out-of-order))))
         (late (and above
                    (format "%s tells it before %s, which is above it in the file"
                            (org-truss-pattern-name (org-truss-cluster-telling up))
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
               ;; Told where a link stands, it is named by that: the role
               ;; it plays where it is written says nothing here.
               (if link (concat (org-truss--mark 'item) "told") (org-truss--role-word model member))
               (if folded (org-truss--fold-mark nested) "")
               (if looping (propertize " [loop]" 'face 'org-truss-attention) "")
               (if late (propertize " ⚠" 'face 'org-truss-attention) ""))
       (car label)
       (car reader)
       (if late (append item (list :why late)) item))
      (and (or link (not in-structure)) (org-truss--id-text member link)))
     (append
       (org-truss--lines-under-heading
        under (cdr label) (org-truss--notes-shown (org-truss-member-notes member)) (cdr reader) item
        (and patterned (not folded)
             (org-truss--line
              (concat under (propertize (format "(%s)" (org-truss-patterns-label member))
                                        'face 'org-truss-dim))
              nil nil (list :type 'member :pos (org-truss-member-pos member)
                            :key (append key '(pattern)))))
        stem)
       (and full (org-truss--use-lines model member stem key))
       (and full (org-truss--grounds-lines model member stem key))
       (and (not folded) (org-truss--links-lines model member stem key))
       ;; Under that line, what is under the member leaves its columns at
       ;; the start of the right.
       (let ((i 0))
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
       (mapcar (lambda (gap)
                 (org-truss--line
                  (concat under "  " (org-truss--gap-text member gap))
                  nil nil (list :type 'member :pos (org-truss-member-pos member)
                                :gap (cons (car gap) (cadr gap))
                                :key (append key (list 'gap (car gap) (cadr gap))))))
               (and full (org-truss-gaps member))))))))

(defun org-truss--links-lines (model holder indent path)
  "Return board lines for the members HOLDER of MODEL tells by its links.
HOLDER is any heading, and its links [[truss-include:m7]] are drawn in the
order they are written, each member as `org-truss--member-lines' draws
it.  PATH identifies HOLDER's lines.  A link HOLDER stands on is drawn as
its ground instead; see `org-truss--told-links'."
  (mapcan (lambda (ref)
            (let ((member (org-truss-heading-by-ref model ref))
                  (key (list 'link path ref)))
              (cond
               ((org-truss-section-p member)
                ;; A section told by a link is drawn where it is written, in
                ;; the structure's tree; here it is one line, the end of
                ;; the link.
                (list (org-truss--with-id
                       (org-truss--line
                        (concat indent (org-truss--mark 'item) "told")
                        (org-truss-section-label member)
                        (car (org-truss--reader-lines (cons (org-truss-section-title member)
                                                            (cdr (org-truss-section-public member)))))
                        (list :type 'section :pos (org-truss-section-pos member)
                              :label (org-truss-section-label member)
                              :link ref :holder (org-truss-cluster-pos holder) :key key))
                       (org-truss--id-text member ref))))
               (member
                (org-truss--member-lines model member indent key ref
                                         (org-truss-cluster-pos holder)))
               (t
                (list (org-truss--line
                       (concat indent (org-truss--mark 'item)
                               (propertize "broken link" 'face 'org-truss-attention))
                       (propertize (org-truss--include-link ref) 'face 'org-truss-attention)
                       nil (list :type 'broken :pos (org-truss-cluster-pos holder)
                                 :link ref :holder (org-truss-cluster-pos holder) :key key)))))))
          (org-truss--told-links holder)))

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

(defun org-truss--section-lines (model section prefix last path parent)
  "Return board lines for SECTION and the sections below it.
PREFIX draws the tree to the left; LAST says SECTION ends its siblings.
PATH is the labels from the root, which identifies the line across redraws.
PARENT is the section above.  A section that comes below one the
parent's telling pattern tells after is marked.  Under a pattern written
out as a list, its right opens with the number, the bullet or the role
the reader sees it with, as a member's does.  It folds as a member does:
holding more than `org-truss-board-fold-limit', it starts folded, and its
line says how many it hides."
  (let* ((path (append path (list (org-truss-section-label section))))
         (inner (concat prefix (if last "  " "│ ")))
         (key (list 'section path))
         (includes (org-truss--told-links section))
         (all (org-truss-section-children section))
         (nested (+ (length (org-truss--section-descendants section)) (length includes)))
         (folded (and (> nested 0)
                      (org-truss--folded-p key (org-truss--over-limit-p
                                                (+ (length all) (length includes))))))
         (children (and (not folded) all))
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
         (n (and parent (org-truss-list-form parent) (not (org-truss-noexport-p section))
                 (seq-position (seq-remove #'org-truss-noexport-p (org-truss-section-children parent))
                               section)))
         (marker (and n (org-truss--list-marker parent section (1+ n))))
         (reader (if (org-truss-noexport-p section)
                     (list (propertize "noexport" 'face 'org-truss-dim))
                   (org-truss--reader-lines
                    (cons (if marker (concat (car marker) (cdr marker) title) title) (cdr public)))))
         (item (append (list :type 'section :pos (org-truss-section-pos section)
                             :label (org-truss-section-label section)
                             :key key)
                       (and (> nested 0) (list :fold key :folded folded)))))
    (append
     (list (org-truss--line (concat prefix (if last "└ " "├ ")
                                    (org-truss--role-word model section)
                                    (if folded (org-truss--fold-mark nested) "")
                                    (if late (propertize " ⚠" 'face 'org-truss-attention) ""))
                            (car label)
                            (car reader)
                            (append item (and (not (string-empty-p why)) (list :why why)))))
     (org-truss--lines-under-heading inner (cdr label) (org-truss--notes-shown (org-truss-section-notes section)) (cdr reader) item
                             (and (not folded) (org-truss--pattern-line section inner item)) stem)
     (and (not folded) (org-truss--grounds-lines model section stem (plist-get item :key)))
     (and (not folded) (org-truss--links-lines model section stem path))
     (let ((n (length children)) (i 0))
       (mapcan (lambda (child)
                 (setq i (1+ i))
                 (org-truss--section-lines model child inner (= i n) path section))
               children))
     (and (not folded) (org-truss--section-gap-lines section (concat inner "  ") item)))))

(defun org-truss--check-heading (name)
  "Return the line that heads the check NAME, saying what it finds on hover."
  (org-truss--line (propertize (concat " " name) 'face 'org-truss-section
                               'help-echo (org-truss-check-about name))))

(defun org-truss--part-of (cluster)
  "Return the part CLUSTER is in: `brief', `subject', `members' or `structure'."
  (cond ((org-truss-member-p cluster) (org-truss-member-home cluster))
        ((org-truss-section-p cluster) 'structure)
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
                         ((org-truss-part-p cluster) (capitalize (symbol-name (org-truss-part-name cluster))))
                         (t (org-truss--role-word model cluster))))
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
         (broken (funcall in (plist-get checks :broken-links)))
         (found (funcall in (append (plist-get checks :broken-grounds)
                                    (plist-get checks :broken-sources)
                                    (mapcar (lambda (l) (cons (car l) (list 'loop (cdr l))))
                                            (plist-get checks :loops))
                                    (mapcan (lambda (id)
                                              (mapcar (lambda (c) (cons c (list 'duplicate id)))
                                                      (seq-filter (lambda (c) (equal (org-truss-cluster-id c) id))
                                                                  (org-truss-clusters model))))
                                            (plist-get checks :duplicates)))))
         (lines
          (append
           (and (or found broken)
                (cons (org-truss--check-heading "Broken links")
                      (append
                       (cdr (org-truss--check-group
                             model "Broken links" found
                             (lambda (e)
                               (cond ((eq (car-safe (cdr e)) 'duplicate)
                                      (format "#%s, which another heading has too" (cadr (cdr e))))
                                     ((consp (cdr e))
                                      (format "%s tells it back" (org-truss--include-link (cadr (cdr e)))))
                                     ((string-prefix-p "[[" (cdr e)) (format "%s not found" (cdr e)))
                                     (t (format "%s not found" (funcall refs (list (cdr e)))))))))
                       (mapcar (lambda (b)
                                 (org-truss--line
                                  "   "
                                  (propertize (format "%s ← %s" (org-truss--include-link (cdr b))
                                                      (org-truss-cluster-label (car b)))
                                              'face 'org-truss-attention)
                                  nil (list :type 'broken :pos (org-truss-cluster-pos (car b))
                                            :link (cdr b) :holder (org-truss-cluster-pos (car b))
                                            :key (list 'broken (cdr b)))))
                               broken))))
           (org-truss--check-group
            model "No grounds" (funcall in (mapcar #'list (plist-get checks :no-grounds)))
            (lambda (_) "no grounds"))
           (org-truss--check-group
            model "Weak grounds" (funcall in (plist-get checks :weak-grounds))
            (lambda (e) (format "%s has no grounds" (funcall refs (list (cdr e))))))
           (org-truss--check-group
            model "Mixed sources" (funcall in (plist-get checks :mixed-sources))
            (lambda (e) (format "points into %s" (string-join (cdr e) ", "))))
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

(defun org-truss--part-line (name gloss item &optional reader)
  "Return the line that opens the part NAME on the board.
GLOSS says what is done there; READER, what the document opens with."
  (org-truss--line (concat " " (propertize name 'face 'org-truss-section)
                           (propertize (concat "  " gloss) 'face 'org-truss-dim))
                   nil reader item))

(defun org-truss--part-lines (model part gloss)
  "Return the lines of PART of MODEL on the board: the brief, the subject or
the members.  Its own line, with GLOSS, saying what is done there; the
patterns it names; the members right under it, each drawn as any member
is; and a line for each role its patterns ask for and none plays, on which
a new member plays it."
  (let* ((name (org-truss-part-name part))
         (item (list :type 'brief :pos (org-truss-part-pos part)
                     :key (list 'brief name) :part name)))
    (append
     (list (org-truss--part-line (capitalize (symbol-name name)) gloss item))
     (delq nil (list (org-truss--pattern-line part " " item)))
     (mapcan (lambda (m)
               (org-truss--member-lines model m "   " (list 'member (org-truss-member-label m))))
             (org-truss-part-children part))
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
            (list (org-truss--part-line "Structure" "how it is told: sections, telling members"
                                        item (car lead)))
            (org-truss--lines-under-heading " " nil (org-truss--notes-shown (org-truss-section-notes root)) (cdr lead) item
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
  "Return the head of the board for MODEL: the title.
In the middle the file's #+title, on the right the title the document is
written under; see `org-truss-document-title'."
  (let ((title (org-truss-model-title model))
        (told (org-truss-document-title model))
        (pos (alist-get '(title) (org-truss-model-locations model) nil nil #'equal)))
    (list (org-truss--line
           (concat " Title" (if (buffer-modified-p (org-truss-model-buffer model))
                                (propertize "  unsaved" 'face 'org-truss-attention)
                              ""))
           (propertize (or title "") 'face 'org-truss-section)
           (and told (propertize (org-truss--link-text told) 'face 'org-truss-reader))
           (and pos (list :type 'brief :pos pos :key '(brief title)))))))

(defun org-truss--members-part (model checks)
  "Return the members part of the board for MODEL, then what is left to do.
Drawn as the brief and the subject are.  On the board of one heading of a
file that is no truss file, that heading, as a part of its own."
  (let ((root (with-current-buffer (org-truss-model-buffer model)
                (org-with-wide-buffer (org-truss--root-pos))))
        (part (org-truss-model-members-part model)))
    (append
     (cond (root
            (cons (org-truss--line "")
                  (cons (org-truss--part-line "Heading" "one heading, read as a truss file's members are"
                                              (list :type 'brief :pos root :part 'members
                                                    :key '(brief members)))
                        (mapcan (lambda (m)
                                  (org-truss--member-lines model m "   " (list 'member (org-truss-member-label m))))
                                (org-truss-model-members model)))))
           (part
            (cons (org-truss--line "") (org-truss--part-lines model part "what is made of it"))))
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

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

(defface org-truss-outline '((t :inherit bold))
  "Face for the words of a part, a check, and a member of Structure on the board."
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

(defface org-truss-outside '((t :slant italic))
  "Face for the words of a member outside the output document.
One no include link brings into it, or one tagged :noexport:.  Over the
face its words have otherwise, so a heading keeps its level's."
  :group 'org-truss)

(defface org-truss-branch '((t :inherit org-truss-dim))
  "Face for the tree that joins an apex member to its supporting members.
The tree of Structure keeps the default face, so the two trees read apart
where they meet."
  :group 'org-truss)

;; Every line has two columns.  The left is what the board says the line
;; is, in its own words.  Between them a thin column says how many use a
;; member, where two or more do.  The middle, from one column shared by every line,
;; is the file's words -- a member's words, the title -- with its links
;; read as the reader reads them; the heading is the reader's words, and
;; its text is all the reader is shown but its comments, so the file's
;; words are the output document's.  A member the output document does not
;; have is in the face of what is outside.  What the board says about a
;; member's patterns goes on the line below, so the left stays narrow and
;; the middle stays close to the tree.  A line drawn whole has the
;; member's text follow it in the middle: what the reader sees, then the
;; comments, which stay in the file, dimmed; the patterns stay right under
;; the member's line, above them.

(defcustom org-truss-board-middle-width nil
  "Width of the board's middle, the file's words.
The middle starts in one column, just right of the widest of the board's
own words.  Nil gives it the window from that column to the window's
edge, never less than 20; a number fixes it.  Words too long for it are
cut short, the whole of them in the tooltip; a line drawn whole is broken
to fit it."
  :type '(choice (const :tag "To the window's edge" nil) integer)
  :group 'org-truss)

(defcustom org-truss-board-image-height 15
  "Most lines a picture takes on a line of the board drawn whole.
A picture linked on a line of its own is drawn in its column, as wide as
the column and no taller than this; elsewhere it is its file's name."
  :type 'integer
  :group 'org-truss)

(defcustom org-truss-board-marks
  '((ground . "⏚") (includes . "•"))
  "The marks the board says a link with, by what is at its other end.
`ground', what a member stands on: on a line of its own under it, a
source its text links to, the words it quotes or, drawn as included, a
member it points to; and after its words, before the ID of a member it
stands on that no member has or that has no grounds itself.
`includes', on the line of a member the member above includes by its
include link, [[truss-include:m7]].  One character each, as wide as a
letter where the board is drawn, keeps the tree in line."
  :type '(alist :key-type symbol :value-type string)
  :group 'org-truss)

(defcustom org-truss-board-quote-marks
  '((found . "✓") (missing . "✗") (unchecked . "?"))
  "The marks just before a quote's words, by what its source was found to say.
`found', its words are in the source; `missing', they are not, and the
quote is listed under Quotes not found; `unchecked', the source's text
cannot surely be read -- a PDF, a picture, a file in an unknown coding,
none linked -- and was not looked in.  See `org-truss-quote-found'."
  :type '(alist :key-type symbol :value-type string)
  :group 'org-truss)

(defcustom org-truss-board-where-marks
  '((link . "↪") (original . "") (others . "+") (ghost . "◌"))
  "The marks just before a line's words saying where else the member is.
`link', before the part the member a line's words link to is written
in, ↪Subject.  Where Structure is drawn as included, a member drawn in
more than one place is drawn in full once, the original, and is one
line, a ghost, wherever else: `original' and `others' before how many
ghosts it has, +1; `ghost' before the member of Structure the original
is under, ◌Sky.  See `org-truss--lane-text'."
  :type '(alist :key-type symbol :value-type string)
  :group 'org-truss)

(defcustom org-truss-board-truss-marks
  '((simple . "△") (compound . "▲"))
  "The marks before the patterns of an apex member, by the shape of its truss.
`simple', a truss whose supporting members are all end members;
`compound', one with an apex member among them; see
`org-truss-truss-shape'.  Seen the same whether the supporting members
are written as headings or as items of a list."
  :type '(alist :key-type symbol :value-type string)
  :group 'org-truss)

(defun org-truss--patterns-text (member)
  "Return how the board names MEMBER's patterns, its truss's mark first.
Nil when it has none."
  (let ((label (org-truss-patterns-label member)))
    (and label
         (concat (alist-get (org-truss-truss-shape org-truss--model member) org-truss-board-truss-marks "")
                 (format " (%s)" label)))))

(defcustom org-truss-board-fold-limit 0
  "How many members right under a member the board shows before folding it.
A member holding more -- its supporting members and those its include
links include -- starts folded, as one line that says how many it hides;
\\<org-truss-board-mode-map>\\[org-truss-board-cycle] unfolds it.  0, as it
is at first, starts every one folded, as an Org file starts in overview
and as \\[universal-argument] \\[org-truss-board-cycle] folds the board;
nil starts it open."
  :type '(choice (const :tag "Start open" nil) integer)
  :group 'org-truss)

(defun org-truss--over-limit-p (n)
  "Non-nil when N members are more than `org-truss-board-fold-limit'."
  (and org-truss-board-fold-limit (> n org-truss-board-fold-limit)))

(defvar org-truss--folding nil
  "How the lines of the board being drawn are shown; see `org-truss--folds'.")

(defun org-truss--folded-p (key default)
  "Non-nil when the line keyed KEY is folded; DEFAULT if it was not set."
  (let ((state (assoc key org-truss--folding)))
    (if state (eq (cdr state) 'folded) default)))

(defvar org-truss--all-whole nil
  "Non-nil while every line of a board is drawn whole.")

(defun org-truss--whole-p (key)
  "Non-nil when the line keyed KEY is drawn whole.
Its words broken to fit, and under a member its text, rather than on one
line cut short; see `org-truss--folds'."
  (or org-truss--all-whole (eq (cdr (assoc key org-truss--folding)) 'whole)))

(defun org-truss--fold-mark (n)
  "Return what a folded line shows of the N members it hides."
  (propertize (format " ▸%d" n) 'face 'org-truss-dim))

(defvar org-truss--middle-width 40
  "Width given the middle, the file's words, while a board is drawn.")

(defvar org-truss--middle-column 0
  "The column the middle starts at, while a board is drawn.")

(defvar org-truss--images nil
  "Non-nil while a board is drawn where pictures can be shown.")

(defvar org-truss--base-directory nil
  "The directory of the truss file whose board is being drawn.
A link to a file by a relative path is read from it.")

(defvar org-truss--whole nil
  "Non-nil while the lines of a member are drawn whole, with its text.")

(defvar org-truss--in-structure nil
  "Non-nil while Structure is drawn.
There a member brings only what the output document has of it: not its
sources, nor what its patterns still ask for.
Elsewhere it brings all of them.")

(defvar org-truss--uses nil
  "While a board is drawn, how each member is used, by the member.
\(INCLUDERS . STANDING): the members whose include links include it, and
those that stand on it, each in the order of the file.")

(defvar org-truss--in-document nil
  "While a board is drawn, the members in the output document.
Those Structure's include links bring into it, with every member under
them and those these include in turn; see `org-truss-in-document'.")

(defvar org-truss--drawing nil
  "While a member is drawn, it and the members it is drawn under or included by.
One among them drawn again would be drawn without end.")

(defvar org-truss--order 'written
  "Where a board opens a member Structure includes: `written' or `included'.
As written, where it is written, with every member under it, and
Structure has it on one line.  As included, under the Structure member
that includes it, with all it brings where it is written -- its sources,
its gaps -- and below its sources the members it stands on, each drawn
so in turn: Structure, the trusses it calls, the facts they stand on, in
one tree.  What Structure brings so is left out where it is written,
`org-truss--chained', so what is left there is used nowhere; one drawn
there again is one line, folded.  A line folded can be unfolded.")

(defvar org-truss--checks nil
  "What `org-truss-checks' says of the board being drawn.")

(defvar org-truss--chained nil
  "While a board is drawn as included, the members Structure brings, or nil.
A hash table, see `org-truss--chain'.  They are drawn under Structure,
and left out where they are written.")

(defvar org-truss--in-list nil
  "Non-nil while the member to be drawn is a list item in the output document.
So is everything under it; see `org-truss-support-form'.")

(defvar org-truss--headless nil
  "Non-nil while the member to be drawn is drawn without its own line.
Its words, then, are the line above's; see `org-truss--brought-lines'.")

(defvar org-truss--shown nil
  "While Structure is drawn as included, the members drawn in it so far.
A hash table, from each to the name of the member of Structure it was
drawn under, as `org-truss--where-label' gives it.  One drawn again
starts folded, and says where it was drawn; see `org-truss--lane-text'.")

(defvar org-truss--telling nil
  "While Structure is drawn, the member of it being drawn, or nil.")

;;;; Drawing

(defun org-truss--line (left &optional middle note item)
  "Return one board line, laid out later by `org-truss-board-text'.
LEFT is what the board says the line is.  MIDDLE is the file's words for
it, and NOTE what a check says of it, after them.  ITEM is what the line
stands for, kept as a text property for the commands; its :why, if any,
is the line's help.  Made while `org-truss--whole', the line is drawn
whole; see `org-truss--whole-lines'."
  (list :left left :middle middle
        :note (and note (not (string-empty-p note)) note)
        :item item :whole org-truss--whole))

(defun org-truss--parts-text (model words)
  "Return where the members the links in WORDS point to are, or nil.
WORDS are a member's as written; a link in them, [[#m7]] or
[[truss-include:m7]], leaves the board's middle naming only the link, so
the part the member it names is written in -- Brief, Subject, Message,
Structure -- is said beside it, as near to its sources as it
is, ↪Subject; see `org-truss-board-where-marks'."
  (let ((parts (seq-uniq
                (delq nil (mapcar
                           (lambda (id)
                             (let ((member (org-truss-member-by-id model id)))
                               (and member (capitalize (symbol-name (org-truss-member-part member))))))
                           (append (org-truss--includes-in words) (org-truss--points-in words)))))))
    (and parts (propertize (concat (alist-get 'link org-truss-board-where-marks)
                                   (string-join parts "/"))
                           'face 'org-truss-dim
                           'help-echo "Written in this part: the words are a link to it"))))

(defun org-truss--with-id (line id)
  "Return LINE naming a member by ID, or LINE as it is.
ID is how a link to the member is written, [[#m9]], or the member itself
is pointed to, #m9; see `org-truss--id-text'.  The mouse on the dots
before the line's words says it."
  (if id (append line (list :id id)) line))

(defun org-truss--with-place (line place)
  "Return LINE with PLACE among the marks before its words, or LINE as it is.
PLACE is the part the member its words link to is written in; see
`org-truss--parts-text'."
  (if place (append line (list :place place)) line))

(defun org-truss--with-lane (line lane)
  "Return LINE with LANE last among the marks before its words, or LINE as it is.
See `org-truss--lane-text' and `org-truss--quote-mark'."
  (if lane (append line (list :lane lane)) line))

(defun org-truss--marks-text (line)
  "Return the marks LINE has just before its words, or nil.
Where the member its words link to is written, and then its thin
column's; no two lines' marks need line up, so each takes no more room
than it needs."
  (let ((marks (delq nil (list (plist-get line :place) (plist-get line :lane)))))
    (and marks (string-join marks " "))))

(defun org-truss--id-text (member &optional id)
  "Return how the board names MEMBER by its ID, or nil.
With ID, when the line is a link to it -- an include link, a ground --
as [[#m9]], or [[m9]] for an item; else as anything points to it, #m9,
or <<m9>> for an item, where it is written."
  (let ((item (org-truss-item-p member)))
    (cond ((and id item) (format "[[%s]]" id))
          (id (format "[[%s]]" (org-truss--pointing-target id)))
          ((and item (org-truss-member-id member)) (format "<<%s>>" (org-truss-member-id member)))
          ((org-truss-member-id member) (concat "#" (org-truss-member-id member))))))

(defun org-truss--leader (width &optional help)
  "Return WIDTH columns that lead the eye from the board's words to the file's.
A space at each end; dots between, when there is room for one, HELP, if
any, what the mouse on them says."
  (let ((dots (/ (- width 2) (char-width ?·))))
    (if (< dots 1)
        (make-string width ?\s)
      (concat " " (propertize (make-string dots ?·) 'face 'org-truss-dim 'help-echo help)
              (make-string (- width 1 (* dots (char-width ?·))) ?\s)))))

(defun org-truss--lay-out (line column)
  "Return LINE as text, with its middle starting at COLUMN.
A middle wider than its room is cut short, the whole of it in the
tooltip, and so is one that leaves its note no room after it, down to
half its room; past that the window cuts the note.  The line's marks,
`org-truss--marks-text', come right before the middle, and the dots
from the left run up to them; the mouse on the dots names the member by
its ID, if the line has one."
  (let* ((marks (org-truss--marks-text line))
         (left (plist-get line :left))
         (note (plist-get line :note))
         (room (if note
                   (max (/ org-truss--middle-width 2)
                        (- org-truss--middle-width 2 (string-width note)))
                 org-truss--middle-width))
         (middle (let ((middle (plist-get line :middle)))
                   (if (and middle (> (string-width middle) room))
                       (propertize (truncate-string-to-width middle (max 1 room) nil nil "…")
                                   'help-echo middle)
                     middle)))
         (why (plist-get (plist-get line :item) :why))
         (gap (- column (string-width left) (if marks (1+ (string-width marks)) 0)))
         (out (if (or marks (and middle (or note (not (string-empty-p middle)))))
                  (concat left
                          (if (or (plist-get line :bare) (string-blank-p left) (null middle))
                              (make-string gap ?\s)
                            (org-truss--leader gap (plist-get line :id)))
                          (cond ((null marks) "")
                                ((or (null middle) (string-empty-p middle)) marks)
                                (t (concat marks " ")))
                          (or middle ""))
                left)))
    (when note
      (setq out (concat out "  " note)))
    ;; A line holding a slice is as high as the slice, with no spacing
    ;; added, so the slices of a picture meet.
    (setq out (propertize (concat out (if (text-property-not-all 0 (length out) 'display nil out)
                                          (propertize "\n" 'line-height t)
                                        "\n"))
                          'org-truss-item (plist-get line :item)))
    (if why (propertize out 'help-echo why) out)))

(defun org-truss--role-names (member)
  "Return the roles MEMBER plays in the patterns above, as the board names them.
Joined, in the order of their kinds; nil when it plays none."
  (let ((roles (org-truss-member-roles member)))
    (and roles (mapconcat (lambda (kind)
                            (let ((role (alist-get kind roles)))
                              (and role (org-truss-role-name role))))
                          (seq-filter (lambda (kind) (alist-get kind roles)) org-truss-pattern-kinds)
                          " · "))))

(defun org-truss--no-role-p (member)
  "Non-nil when the board being drawn finds MEMBER playing no role it should."
  (assq member (plist-get org-truss--checks :no-role)))

(defun org-truss--no-pattern-p (member)
  "Non-nil when the board being drawn finds MEMBER playing a role the
member above has no pattern for."
  (assq member (plist-get org-truss--checks :no-pattern)))

(defun org-truss--role-word (model member)
  "Return the board's word for MEMBER of MODEL, on the left of its line.
The roles it plays in the patterns of the member above, or `member' when
it plays none; then [no role] when it plays none of a pattern above it,
[no pattern] when it plays a role the member above has no pattern for,
[assumed] when it is tagged :assumption:, [noexport] when it is tagged
:noexport:, and [no grounds] when it must have grounds and lacks them,
each in its face."
  (concat (or (org-truss--role-names member) "member")
          (if (org-truss--no-role-p member) (propertize " [no role]" 'face 'org-truss-attention) "")
          (if (org-truss--no-pattern-p member) (propertize " [no pattern]" 'face 'org-truss-attention) "")
          (if (org-truss-assumption-p member) (propertize " [assumed]" 'face 'org-truss-tentative) "")
          (if (org-truss-noexport-p member) (propertize " [noexport]" 'face 'org-truss-dim) "")
          (if (org-truss-missing-grounds model member)
              (propertize " [no grounds]" 'face 'org-truss-attention)
            "")))

(defun org-truss--link-text (text)
  "Return TEXT with each link read as its description, or else its target.
A link to a file without one reads as the file's name, and a pointing or
include link as the member's words."
  (replace-regexp-in-string
   "\\[\\[\\*?\\([^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]"
   (lambda (link)
     (let ((target (match-string 1 link)))
       (or (match-string 2 link)
           (save-match-data
             (and (string-match "\\`\\(?:file:\\|\\.\\.?/\\)\\([^:]+\\)" target)
                  (file-name-nondirectory (org-link-unescape (match-string 1 target)))))
           (let ((member (and org-truss--model
                              (org-truss-member-by-id
                               org-truss--model
                               (org-truss--link-id (string-remove-prefix
                                                    (concat org-truss-include-type ":") target))))))
             (and member (org-truss-member-words member)))
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
paragraphs.  A picture linked on a line of its own is drawn, where the
board can show one, on the lines it takes; see `org-truss--picture-lines'."
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

(defun org-truss--text-lines (body comments &optional outside)
  "Return a member's text as the lines it takes in the middle, drawn whole.
BODY, what the reader sees, its links read as the reader reads them; then
COMMENTS, which stay in the file, as written, each line opened with the
# it is written with, dimmed.  Neither has what the lines below draw;
see `org-truss--text-shown'.  OUTSIDE, the body is in the face of what is
outside the output document, as its member's words are, and only that."
  (let ((width org-truss--middle-width))
    (append (let ((lines (org-truss--fill (or (org-truss--text-shown body) "") width)))
              (if outside (org-truss--outside lines) lines))
            (mapcar (lambda (line)
                      (propertize (if (string-empty-p line) "#" (concat "# " line))
                                  'face 'org-truss-dim))
                    (org-truss--fill (or (org-truss--text-shown comments) "") (- width 2) t)))))

(defun org-truss--level-face (level)
  "Return the face Org gives the words of a heading at LEVEL.
As `org-get-level-face' works it out, for odd levels only and for faces
that cycle or stop at the last."
  (let ((n (if org-odd-levels-only (1+ (/ level 2)) level)))
    (if org-cycle-level-faces
        (nth (% (1- n) org-n-level-faces) org-level-faces)
      (nth (1- (min n org-n-level-faces)) org-level-faces))))

(defun org-truss--member-words (member &optional outside)
  "Return MEMBER's words as the board draws them, its links read.
As the reader reads them: an include link alone, as Structure's members
are written, reads as the words of the member it includes.  OUTSIDE, or
tagged :noexport:, in the face of what is outside the output document; else
a member of Structure in the face of its outline, any other in the face
the file gives a heading of its level.  The board colours them itself,
rather than copy the file's, which is there only where the file has been
shown."
  (let ((face (if (org-truss-in-structure-p member)
                  'org-truss-outline
                (org-truss--level-face (org-truss-member-level member)))))
    (propertize (org-truss--link-text (org-truss-member-words member))
                'face (if (or outside (org-truss-noexport-p member))
                          (list 'org-truss-outside face)
                        face))))

(defun org-truss--words-lines (words &optional marker note)
  "Return WORDS as the lines they are drawn on, after MARKER if any.
MARKER is how the reader sees the member begin, its number, bullet or
role, dimmed; the lines after the first are indented as far, as a list
item's are.  One line, cut short if need be; drawn whole, as many as it
takes to break them to the room of the middle, since the line is then
read rather than scanned, leaving room for NOTE, if any, beside them."
  (let ((hang (if marker (string-width marker) 0)))
    (cl-loop for line in (if org-truss--whole
                             (org-truss--break words (max 10 (- org-truss--middle-width hang
                                                                (if note (+ 2 (string-width note)) 0))))
                           (list words))
             for first = t then nil
             collect (concat (cond ((not marker) "")
                                   (first (propertize marker 'face 'org-truss-dim))
                                   (t (make-string hang ?\s)))
                             line))))

(defconst org-truss--link-line-re
  "^[ \t]*\\(?:[-+] \\)?\\[\\[[^]\n]+\\]\\(?:\\[[^]\n]*\\]\\)?\\][ \t]*\\(?:\n\\|\\'\\)"
  "A line holding nothing but a link, as a list item or not.")

(defun org-truss--text-shown (text)
  "Return TEXT without its quotations and the lines holding nothing but a link.
TEXT is a member's, its comments or what the output document shows.
Each of those is a ground, words quoted or a member or a source it stands
on, or a member it includes, which the board draws on a line of its own,
marked; it would be drawn twice."
  (when text
    (dolist (block (reverse (org-truss--quote-blocks text)))
      (setq text (concat (substring text 0 (car block)) (substring text (cadr block)))))
    (string-trim (replace-regexp-in-string org-truss--link-line-re "" text))))

(defun org-truss--lines-under-words (left more text item &optional head stem)
  "Return the lines under a member's own line on the board.
HEAD, if any, is the line naming its patterns.  Drawn whole, MORE, the
rest of the member's words, and then TEXT, the lines of its text, go in
the middle.  LEFT starts each line, and STEM, when given, each line
below HEAD, or every line without one: the line of the tree down to what
branches off under the member.  ITEM is the member's line's, kept under
a key of its own.

HEAD's words take the left of the first of these lines, so they stay
right under the member's line.  When they are too wide for the left they
take the line after the member's own words instead, and the middle
leaves that line to them."
  (if (not org-truss--whole)
      (and head (list head))
    (let* ((wide (and head (> (+ (string-width (plist-get head :left)) 2)
                              org-truss--middle-column)))
           (at (cond (wide (length more)) (head 0) (t -1)))
           (middle (append more (and wide (list nil)) text)))
      (cl-loop for i below (max (length middle) (1+ at))
               collect (append (if (= i at)
                                   (org-truss--line (plist-get head :left) (nth i middle)
                                                    nil (plist-get head :item))
                                 (org-truss--line (if (and stem (> i at)) stem left)
                                                  (or (nth i middle) "") nil
                                                  (plist-put (copy-sequence item) :key
                                                             (append (plist-get item :key)
                                                                     (list 'text i)))))
                               '(:bare t))))))

(defun org-truss--whole-lines (line)
  "Return LINE as the lines it takes drawn whole.
Its middle is broken to its room, and what does not fit goes on lines of
its own below, which start with LINE's :under, the tree on its left
going on down; its note, when it does not fit beside the middle, follows
it so.  A member's words and text are broken where they are drawn, to
keep them in order with what is under it; this breaks the rest: a
ground, what a check lists."
  (let* ((note (plist-get line :note))
         (middle (plist-get line :middle))
         (beside (and note middle
                      (<= (+ (string-width middle) 2 (string-width note)) org-truss--middle-width)))
         (middles (append (and middle (org-truss--break middle org-truss--middle-width))
                          (and note (not beside) (org-truss--break note org-truss--middle-width))))
         (item (plist-get line :item)))
    (if (null (cdr middles))
        (list line)
      (cons (plist-put (plist-put (copy-sequence line) :middle (car middles)) :note nil)
            (cl-loop for i from 1 below (length middles)
                     collect (append (org-truss--line
                                      (or (plist-get line :under) "")
                                      (nth i middles) nil
                                      (and item
                                           (plist-put (copy-sequence item) :key
                                                      (append (plist-get item :key)
                                                              (list 'wrap i)))))
                                     '(:bare t)))))))

(defconst org-truss--mark-help
  '((ground . "Its grounds: what this member stands on, linked in its text")
    (includes . "Included by the member above: its include link, [[truss-include:id]], includes this member, and the output document has it here"))
  "What the mark of each kind of link says.")

(defun org-truss--mark-only (kind)
  "Return the mark of a link of KIND; the mouse on it says what it means.
See `org-truss-board-marks'."
  (propertize (or (alist-get kind org-truss-board-marks) "?")
              'face 'org-truss-dim
              'help-echo (alist-get kind org-truss--mark-help)))

(defun org-truss--mark (kind)
  "Return the mark of a line naming the other end of a link of KIND, and a space."
  (concat (org-truss--mark-only kind) " "))

(defun org-truss--grounds-note (model member)
  "Return the members MEMBER of MODEL stands on that it cannot, or nil.
Drawn after its words, after the mark of a ground: the ID of each that
no member has, or that has no grounds itself, ⏚m7, in the face of what
wants doing.  The members it stands on that hold are not named: drawn as
included, `org-truss--order', they are drawn below it."
  (let ((trouble (delq nil (mapcar (lambda (id)
                                     (let ((ground (org-truss-member-by-id model id)))
                                       (and (not (and ground (org-truss-holds-p ground)))
                                            (propertize id 'face 'org-truss-attention
                                                        'help-echo (if ground "It has no grounds"
                                                                     "No member has this ID")))))
                                   (org-truss-member-grounds member)))))
    (and trouble (concat (org-truss--mark-only 'ground) (string-join trouble " ")))))

(defun org-truss--users (member)
  "Return the members that use MEMBER, standing on it or including it, each once.
As `org-truss--uses' has them."
  (let ((use (and org-truss--uses (gethash member org-truss--uses))))
    (seq-uniq (append (car use) (cdr use)))))

(defun org-truss--linked-to (model member)
  "Return the members MEMBER of MODEL stands on or includes, each once."
  (delq nil (mapcar (lambda (id) (org-truss-member-by-id model id))
                    (seq-uniq (append (org-truss-member-grounds member)
                                      (org-truss--included member))))))

(defun org-truss--chain-uses (model member)
  "Return how many places of the output document's chain draw MEMBER of MODEL.
The members of Structure and those it brings, `org-truss--chained', that
stand on it or include it, see `org-truss--users'; and the member it is
under, when the chain has that one, which brings it as its own -- once,
when that one stands on it too."
  (let ((in-chain (lambda (m) (and m (or (org-truss-in-structure-p m)
                                         (and org-truss--chained (gethash m org-truss--chained)))))))
    (length (seq-uniq (seq-filter in-chain (cons (org-truss-parent model member)
                                                 (org-truss--users member)))))))

(defun org-truss--where-label (member)
  "Return how the thin column names MEMBER of Structure, or Structure for nil.
By the roles it plays, Sky; one that plays none, by its words cut short."
  (cond ((null member) "Structure")
        ((org-truss--role-names member))
        (t (truncate-string-to-width (org-truss-member-words member) 10 nil nil "…"))))

(defun org-truss--lane-text (model member before)
  "Return what the thin column says of MEMBER of MODEL, drawn as included.
In Structure's chain.  BEFORE, when it was drawn there before, names the
member of Structure it was drawn in full under, ◌Sky: this is a ghost of
it, read there, one line here.
Else, how many ghosts it has, +1, when the chain draws it in more than
one place: all of them stand on it, so it is checked first; see
`org-truss--chain-uses'.  Nil when neither.  See
`org-truss-board-where-marks'."
  (if before
      (propertize (concat (alist-get 'ghost org-truss-board-where-marks) before)
                  'face 'org-truss-dim
                  'help-echo (format "A ghost: drawn in full above, under %s" before))
    (let ((n (org-truss--chain-uses model member)))
      (and (> n 1)
           (propertize (concat (alist-get 'original org-truss-board-where-marks)
                               (alist-get 'others org-truss-board-where-marks)
                               (number-to-string (1- n)))
                       'face 'org-truss-dim
                       'help-echo (format "Drawn in full here, and as a ghost in %d more places of the output document's chain"
                                          (1- n)))))))

(defun org-truss--linked-positions (model member &optional including)
  "Return the positions of the members MEMBER of MODEL stands on.
And, INCLUDING, of those it includes, which no line under it names.
Kept on its line as :names, so the lines naming them light up with it."
  (delq nil (mapcar (lambda (id)
                      (let ((m (org-truss-member-by-id model id)))
                        (and m (org-truss-member-pos m))))
                    (seq-uniq (append (org-truss-member-grounds member)
                                      (and including (org-truss-member-includes member)))))))

(defun org-truss--member-item (member &rest more)
  "Return the item of a line naming MEMBER, with MORE, a plist, after it.
Its :type is `member', and :structure is non-nil for a member of
Structure."
  (append (list :type 'member :pos (org-truss-member-pos member)
                :words (org-truss-member-words member))
          (and (org-truss-in-structure-p member) (list :structure t))
          more))

(defun org-truss--outside (lines)
  "Return LINES, a member's text, in the face of what is outside."
  (mapcar (lambda (line) (and line (propertize line 'face 'org-truss-outside))) lines))

(defun org-truss--included (member)
  "Return the IDs MEMBER's include links include, each once.
Not those it stands on, `org-truss-standing-includes': the board draws a
link as what it is to the member, and those are its grounds."
  (seq-difference (seq-uniq (org-truss-member-includes member))
                  (org-truss-standing-includes member)))

(defun org-truss--member-uses (model)
  "Return how each member of MODEL is used, as `org-truss--uses' keeps it.
An include link a member stands on makes it stand on what it includes;
see `org-truss-standing-includes'."
  (let ((uses (make-hash-table :test #'eq))
        (cell (lambda (m uses) (or (gethash m uses) (puthash m (cons nil nil) uses)))))
    (dolist (m (org-truss-model-members model))
      (dolist (id (org-truss--included m))
        (let ((included (org-truss-member-by-id model id)))
          (when included
            (let ((use (funcall cell included uses)))
              (setcar use (append (car use) (list m))))))))
    (dolist (m (org-truss-model-members model))
      (dolist (id (org-truss-member-grounds m))
        (let ((ground (org-truss-member-by-id model id)))
          (when ground
            (let ((use (funcall cell ground uses)))
              (setcdr use (append (cdr use) (list m))))))))
    uses))

(defun org-truss--branch (indent last)
  "Return how the lines of a supporting member start.
INDENT starts its apex member's lines.  A cons (LINE . UNDER) for
`org-truss--member-lines': LINE branches off to the member, and UNDER
carries the tree down past it to the next, unless the member is the LAST."
  (cons (concat indent (propertize (if last "└ " "├ ") 'face 'org-truss-branch))
        (concat indent (propertize (if last "  " "│ ") 'face 'org-truss-branch))))

(defun org-truss--ground-line (stem key left middle item)
  "Return a line naming what a member stands on, below it.
STEM starts it, with the mark of a ground and LEFT; MIDDLE names it,
dimmed under the faces its own marks have; ITEM is what it stands for,
under KEY."
  (append (org-truss--line (concat stem (org-truss--mark 'ground) left)
                           (and middle (let ((middle (copy-sequence middle)))
                                         (add-face-text-property 0 (length middle) 'org-truss-dim t middle)
                                         middle))
                           nil (plist-put item :key key))
          (list :under stem)))

(defun org-truss--quote-mark (member quote)
  "Return the mark just before QUOTE of MEMBER, in the thin column.
Whether its words were found in its source, were not, or were not looked
for; see `org-truss-board-quote-marks'."
  (let* ((file (and org-truss--model (buffer-file-name (org-truss-model-buffer org-truss--model))))
         (link (and org-truss--model (org-truss-quote-link org-truss--model member quote)))
         (found (or (and link (org-truss-quote-found quote link file)) 'unchecked)))
    (propertize (or (alist-get found org-truss-board-quote-marks) "?")
                'face (if (eq found 'missing) 'org-truss-attention 'org-truss-dim)
                'help-echo (pcase found
                             ('found "Found in its source")
                             ('missing "Not found in its source: copy its words as they are")
                             (_ "Not looked for: its source's text cannot surely be read")))))

(defun org-truss--grounds-lines (member stem key)
  "Return a line for each source MEMBER stands on, below it.
The words it quotes, each quotation, and below them the sources its text
links to, each once, as the words are read from the source; a link among
them that points to nothing said not to be found.  Each keeps the links
to sources it opens, as :links: a source's own, and a quotation's, or
else the first the text cites.  The members it stands on are drawn
below these as included; see `org-truss--ground-members-lines'.  STEM
starts each; KEY is MEMBER's line's."
  (let* ((pos (org-truss-member-pos member))
         (missing (mapcar #'cdr (seq-filter (lambda (b) (eq (car b) member))
                                            (plist-get org-truss--checks :broken-sources))))
         (found-p (lambda (text) (not (seq-some (lambda (link) (string-search link text)) missing)))))
    (append
     (mapcar (lambda (source)
               (org-truss--with-lane
                (org-truss--ground-line stem (append key (list 'source (car source)))
                                        (concat (symbol-name (car source))
                                                (if (funcall found-p (cdr source)) ""
                                                  (propertize " [not found]" 'face 'org-truss-attention)))
                                        (org-truss--one-line (org-truss--link-text (cdr source)))
                                        (list :type 'member :pos pos
                                              :links (if (eq (car source) 'source)
                                                         (list (cdr source))
                                                       (or (org-truss--source-links-in (cdr source))
                                                           (ensure-list (org-truss-member-cited member))))))
                (and (eq (car source) 'quote) (org-truss--quote-mark member (cdr source)))))
             (append (mapcar (lambda (words) (cons 'quote words))
                             (org-truss-member-quoted member))
                     (mapcar (lambda (link) (cons 'source link))
                             (seq-uniq (org-truss-member-source-links member))))))))

(defun org-truss--ground-members (model member)
  "Return the members MEMBER of MODEL stands on that a chain draws under it.
Each once, as its grounds name them; not one of Structure, which is
drawn in Structure's own tree, nor one under MEMBER, drawn there."
  (let ((under (org-truss--subtree member)))
    (delq nil (mapcar (lambda (id)
                        (let ((ground (org-truss-member-by-id model id)))
                          (and ground (not (org-truss-in-structure-p ground)) (not (memq ground under))
                               ground)))
                      (org-truss-member-grounds member)))))

(defun org-truss--ground-members-lines (model holder grounds stem key)
  "Return the lines of GROUNDS, the members of MODEL HOLDER stands on, below it.
Each drawn as any member is, with what is under it and what it stands on
in turn, named by the ID HOLDER links to it by, [[#m7]], and marked as a
reason: one HOLDER includes, by an include link it stands on, as one the
output document has there, an item of a list when the link is in its
text; one it points to, as one the output document leaves out there.
STEM starts each; KEY is HOLDER's line's.  See `org-truss-member-grounds'."
  (let ((standing (org-truss-standing-includes holder))
        (heading (org-truss--includes-in (org-truss-member-words holder))))
    (mapcan (lambda (ground)
              (let* ((id (org-truss-member-id ground))
                     (included (member id standing))
                     (org-truss--in-list (and included (or org-truss--in-list (not (member id heading))))))
                (org-truss--member-lines model ground stem (list 'ground key id)
                                         (and included id) (and included (org-truss-member-pos holder))
                                         (and org-truss--in-list "- ") id)))
            grounds)))

(defun org-truss--stands-for (model member)
  "Return (ID . INCLUDED) when MEMBER of MODEL stands for the member it includes.
When its words are an include link alone, to a member not of Structure;
else nil."
  (and (org-truss-include-alone-p member)
       (let* ((id (car (org-truss-member-includes member)))
              (included (org-truss-member-by-id model id)))
         (and included (not (org-truss-in-structure-p included)) (cons id included)))))

(defun org-truss--brought-count (model member)
  "Return how many lines of members MEMBER of MODEL brings below it.
Those under it, those it stands on and those it includes, as a member
that stands for it counts what it hides; see `org-truss--stands-for'."
  (+ (length (cdr (org-truss--subtree member)))
     (length (org-truss--ground-members model member))
     (length (org-truss--included member))))

(defun org-truss--brought-lines (model member indent key &optional link ground)
  "Return the lines MEMBER of MODEL brings below its own, without that.
Drawn under a member that stands for it, `org-truss--stands-for': that
line is MEMBER's, so its own would say the same words again.  What it
brings -- its patterns, its sources, the members it stands on and those
under it -- follows, open.  INDENT, KEY, and LINK or GROUND, the ID it
is linked by, are as `org-truss--member-lines' takes them."
  (let ((org-truss--folding (cons (cons key 'open) org-truss--folding))
        (org-truss--headless t))
    (cdr (org-truss--member-lines model member indent key link nil nil ground))))

(defun org-truss--chain (model)
  "Return the members of MODEL that Structure brings, as a hash table.
Those its include links include and those its members stand on, with
every member under them, and so on down through what those include and
stand on.  Drawn under Structure as included, `org-truss--order', they
are left out where they are written; what is left there is used nowhere
the output document reaches."
  (let ((chained (make-hash-table :test #'eq))
        (root (org-truss-model-structure model))
        todo)
    (when root
      (dolist (m (org-truss--subtree root))
        (setq todo (append (org-truss--linked-to model m) todo)))
      (while todo
        (let ((m (pop todo)))
          (unless (or (gethash m chained) (org-truss-in-structure-p m))
            (dolist (under (org-truss--subtree m))
              (puthash under t chained)
              (setq todo (append (org-truss--linked-to model under) todo)))))))
    chained))

(defun org-truss--chained-p (member)
  "Non-nil when Structure brings MEMBER on the board being drawn.
Or every member under it, when it has any: nothing of it is left to be
drawn where it is written.  See `org-truss--chained'."
  (and org-truss--chained
       (or (gethash member org-truss--chained)
           (let ((supports (org-truss-member-supports member)))
             (and supports (seq-every-p #'org-truss--chained-p supports))))))

(defun org-truss--gap-lines (member indent item)
  "Return a line for each role MEMBER's patterns ask for and none plays.
At INDENT; ITEM is MEMBER's line's.  On one, a new member plays that role."
  (let ((item (list :type (plist-get item :type) :pos (plist-get item :pos)
                    :structure (plist-get item :structure) :part (plist-get item :part)
                    :key (plist-get item :key))))
    (mapcar (lambda (gap)
              (org-truss--line
               (concat indent (org-truss--gap-text member gap))
               nil nil (append (list :gap (cons (car gap) (cadr gap))
                                     :key (append (plist-get item :key)
                                                  (list 'gap (car gap) (cadr gap))))
                               item)))
            (cdr (assq member (plist-get org-truss--checks :gaps))))))

(defun org-truss--late-text (member parent)
  "Return why MEMBER comes too late below PARENT, or nil.
When the file has it below a member PARENT's telling pattern tells after
it; see `org-truss-out-of-order'."
  (let ((above (cdr (assq member (plist-get org-truss--checks :out-of-order)))))
    (and above
         (format "%s tells it before %s, which is above it in the file"
                 (org-truss-pattern-name (org-truss-member-telling parent))
                 (org-truss-member-words above)))))

(defun org-truss--opening (form)
  "Return what a member's words open with, as FORM says, or nil.
FORM is `org-truss-support-form''s: its bullet, number or role."
  (and (cdr form) (not (string-empty-p (cdr form))) (cdr form)))

(defun org-truss--seen (member)
  "Return the name of the member of Structure MEMBER was drawn in full under.
Nil when it was not drawn in full yet; see `org-truss--shown'."
  (and org-truss--shown (gethash member org-truss--shown)))

(defun org-truss--see (member)
  "Record MEMBER as drawn in full under the member of Structure being drawn."
  (when org-truss--shown
    (puthash member (org-truss--where-label org-truss--telling) org-truss--shown)))

(defun org-truss--member-lines (model member indent key
                                      &optional link holder marker ground)
  "Return board lines for MEMBER and every member under it.
MEMBER is written outside Structure.  INDENT starts each line: a string,
or a cons (LINE . UNDER) for a supporting member, LINE starting its own
line and UNDER the lines under it, as `org-truss--branch' makes them.
Its supporting members branch off right under it; its patterns head
them, and its grounds go in further.  KEY identifies the line across
redraws.  LINK, the ID of the include link that includes MEMBER, and
HOLDER, the position of the member it is in, are set when MEMBER is
drawn there, so the line can be moved.  GROUND, the ID a member standing
on MEMBER links to it by, is set when MEMBER is drawn under that member;
see `org-truss--ground-members-lines'.  MARKER is how the reader sees it
begin: its number or bullet when its apex member's supporting members
are a list in the output document, and the role it plays when the
pattern labels them.  The members its own include links include are
drawn below its grounds; one drawn under itself is drawn as one line,
marked, since it would never end.

Drawn in Structure as included, `org-truss--chained', the members it
stands on follow its sources, each drawn so in turn, and the members
under it written where they are not drawn there are left out where they
are written.  One drawn there before starts folded.

Its line names the members it stands on that it cannot, see
`org-truss--grounds-note'; the mouse on its dots names it as it is
linked, or by its ID where it is written, see `org-truss--with-id'.
Where it is opened, as `org-truss--order'
says, the sources it stands on follow it, and the roles its patterns ask
for and it lacks; where it is not, it starts folded, to one line.  In Structure,
`org-truss--in-structure', only what the output document has comes with
it besides.  Its words and text are in the face of what is outside while
the output document does not have it.  A member the file has below one
its apex member's telling pattern tells after it is marked."
  (let ((looping (memq member org-truss--drawing))
        (org-truss--drawing (cons member org-truss--drawing))
        (org-truss--whole (org-truss--whole-p key))
        (headless org-truss--headless)
        (org-truss--headless nil)
        (listed org-truss--in-list)
        (org-truss--in-list nil))
  (let* ((under (if (consp indent) (cdr indent) indent))
         (indent (if (consp indent) (car indent) indent))
         (in-structure org-truss--in-structure)
         ;; What the output document does not have is drawn so.
         (outside (or (org-truss-noexport-p member)
                      (and (not in-structure) (not (memq member org-truss--in-document)))))
         (note (org-truss--grounds-note model member))
         (words (org-truss--words-lines (org-truss--member-words member outside) marker note))
         ;; In Structure as included, what it stands on comes with it;
         ;; drawn there before, it starts folded.
         (chain (and in-structure (eq org-truss--order 'included)))
         (seen (and chain (org-truss--seen member)))
         (_ (and chain (not seen) (org-truss--see member)))
         ;; One whose words are an include link alone is the member it
         ;; includes: its line stands for both, and no line under it
         ;; names that member again.  In Structure as included, what that
         ;; member brings follows it, once.
         (alone (org-truss--stands-for model member))
         (stands-for (and chain alone))
         (stood-seen (and stands-for (org-truss--seen (cdr stands-for))))
         (brings (and stands-for (not stood-seen)))
         (grounds (and chain (remq (cdr stands-for) (org-truss--ground-members model member))))
         (supports (if in-structure
                       (org-truss-member-supports member)
                     (seq-remove #'org-truss--chained-p (org-truss-member-supports member))))
         (includes (remove (car alone) (org-truss--included member)))
         (nested (+ (length (mapcan #'org-truss--subtree supports)) (length includes) (length grounds)
                    (if brings (org-truss--brought-count model (cdr stands-for)) 0)))
         ;; It is opened in one place, by the order the board is drawn
         ;; in, and starts folded in the other: as written, where it is
         ;; written; as included, where a link includes it.  See
         ;; `org-truss--order'.
         (elsewhere (if (eq org-truss--order 'included)
                        (and (not link) (not in-structure)
                             (car (and org-truss--uses (gethash member org-truss--uses))))
                      (and link t)))
         (folded (or (and looping (> nested 0))
                     (and (> nested 0)
                          (org-truss--folded-p key (or (and elsewhere t) seen
                                                       (org-truss--over-limit-p
                                                        (+ (length supports) (length includes)
                                                           (length grounds))))))))
         (shown (and (not folded) supports))
         ;; What it brings where it is written -- its sources, its gaps --
         ;; it brings where it is opened; not where it is one line, nor
         ;; drawn again but whole.
         (full (and (not folded) (not elsewhere) (or (not seen) org-truss--whole)
                    (or (not in-structure) chain)))
         ;; What comes between its patterns and the members branching off
         ;; below -- its text, its grounds -- has the tree's line run past.
         (stem (concat under (if shown (propertize "│ " 'face 'org-truss-branch) "  ")))
         (item (org-truss--member-item
                member :link link :holder holder :ground ground :key key
                :alone (and brings (org-truss-member-pos (cdr stands-for)))
                :names (org-truss--linked-positions model member)
                :fold (and (not looping) key) :nested (if looping 0 nested)
                :folded (and (> nested 0) (not looping) folded)))
         (late (org-truss--late-text member (org-truss-parent model member))))
    (cons
     ;; Included from Structure, it is named on hover as the link does;
     ;; where it is written, by its ID.  Under a member included there,
     ;; it is not linked to itself, and names nothing.  Drawn in Structure
     ;; as included, the thin column says where it was drawn before, or
     ;; how many use it -- the member it includes, when its words are an
     ;; include link alone.
     (org-truss--with-lane
      (org-truss--with-place
       (org-truss--with-id
        (org-truss--line
         (concat indent
                 ;; Included where a link stands, or stood on, it is named
                 ;; by that: the role it plays where it is written says
                 ;; nothing here.
                 ;; A reason by a link: the output document has it here
                 ;; when the link includes it, and leaves it out when it
                 ;; points to it.
                 (cond (ground (concat (org-truss--mark (if link 'includes 'ground)) "reason"))
                       (link (concat (org-truss--mark 'includes) "included"))
                       (t (org-truss--role-word model member)))
                 (if folded (org-truss--fold-mark nested) "")
                 (if looping (propertize " [loop]" 'face 'org-truss-attention) "")
                 (if late (propertize " ⚠" 'face 'org-truss-attention) ""))
         (car words)
         note
         (if late (append item (list :why late)) item))
        (and (or link ground (not in-structure))
             (org-truss--id-text member (or ground link))))
       (org-truss--parts-text model (org-truss-member-words member)))
      (and chain (if stands-for
                     (org-truss--lane-text model (cdr stands-for) stood-seen)
                   (org-truss--lane-text model member seen))))
     (append
       (org-truss--lines-under-words
        ;; Drawn without its line, its words are the line above's, broken
        ;; there.
        under (and (not headless) (cdr words))
        (and org-truss--whole
             (org-truss--text-lines (org-truss-member-body member) (org-truss-member-notes member)
                                    outside))
        item
        (and (org-truss-apex-p member) (not folded)
             (org-truss--line
              (concat under (propertize (org-truss--patterns-text member) 'face 'org-truss-dim))
              nil nil (org-truss--member-item member :key (append key '(pattern)))))
        stem)
       (and full (org-truss--grounds-lines member stem key))
       ;; What it brings, stands on and includes is where it is in the
       ;; output document, an item when it is one.
       (let ((org-truss--in-list listed))
         (append
          (and full brings
               (org-truss--brought-lines model (cdr stands-for) under
                                         (list 'ground key (car stands-for)) nil (car stands-for)))
          (and full (org-truss--ground-members-lines model member grounds stem key))
          (and (not folded) (org-truss--includes-lines model member stem key (car alone)))))
       (let ((i 0))
         (mapcan (lambda (support)
                   ;; It opens as the output document has it: an item of a
                   ;; list with its bullet, a heading with no bullet.
                   (let* ((form (org-truss-support-form member support listed))
                          (org-truss--in-list (car form)))
                     (org-truss--member-lines model support
                                              (org-truss--branch under (= (setq i (1+ i))
                                                                          (length shown)))
                                              (append key (list (org-truss-member-words support)))
                                              nil nil (org-truss--opening form))))
                 shown))
       (and full (org-truss--gap-lines member (concat under "  ") item)))))))

(defun org-truss--includes-lines (model holder indent path &optional skip)
  "Return board lines for the members HOLDER of MODEL includes.
By its include links.  HOLDER is any member, and its include links are
drawn in the order they are written, each member as
`org-truss--member-lines' draws it.  PATH identifies HOLDER's lines.  An
include link HOLDER stands on is drawn as its ground instead; see
`org-truss--included'.  The link to SKIP, an ID, is not drawn: HOLDER's
own line stands for it; see `org-truss--brought-lines'.  A member
included by a link in HOLDER's text opens as the output document has
it, an item of a list, with all under it; one included on its heading's
line, as headings, unless HOLDER is an item itself,
`org-truss--in-list'."
  (mapcan (lambda (id)
            (let* ((member (org-truss-member-by-id model id))
                   (key (list 'link path id))
                   (org-truss--in-list
                    (or org-truss--in-list
                        (not (member id (org-truss--includes-in (org-truss-member-words holder)))))))
              (cond
               ((and member (org-truss-in-structure-p member))
                ;; A member of Structure included by a link is drawn where it
                ;; is written, in Structure's tree; here it is one line, the
                ;; end of the link.
                (list (org-truss--with-id
                       (org-truss--line
                        (concat indent (org-truss--mark 'includes) "included")
                        (org-truss--member-words member)
                        nil
                        (org-truss--member-item member :link id
                                                :holder (org-truss-member-pos holder) :key key))
                       (org-truss--id-text member id))))
               (member
                (org-truss--member-lines model member indent key id
                                         (org-truss-member-pos holder)
                                         (and org-truss--in-list "- ")))
               (t
                (list (org-truss--line
                       (concat indent (org-truss--mark 'includes)
                               (propertize "broken link" 'face 'org-truss-attention))
                       (propertize (org-truss--include-link id) 'face 'org-truss-attention)
                       nil (list :type 'broken :pos (org-truss-member-pos holder)
                                 :link id :holder (org-truss-member-pos holder) :key key)))))))
          (remove skip (org-truss--included holder))))

(defun org-truss--pattern-line (member indent item)
  "Return the line naming the patterns of MEMBER, a part or Structure's, or nil.
Nil when it has none.  It goes under MEMBER's own line, at INDENT.  ITEM
is MEMBER's line's, kept under a key of its own."
  (let ((label (org-truss--patterns-text member)))
    (and label
         (org-truss--line
          (concat indent (propertize label 'face 'org-truss-dim))
          nil nil (plist-put (copy-sequence item) :key
                             (append (plist-get item :key) '(pattern)))))))

(defun org-truss--asking (member gap)
  "Return the name of the pattern of MEMBER that asks for GAP, or nil.
Nil when MEMBER has that pattern alone, and no other could be asking."
  (and (cdr (org-truss-member-patterns member))
       (org-truss-pattern-name (org-truss-member-pattern member (car gap)))))

(defun org-truss--gap-text (member gap)
  "Return how the board shows GAP of MEMBER, (KIND ROLE . SHORT-BY).
The role, how many more, and, when MEMBER has more than one pattern, the
one that asks for it."
  (let ((asking (org-truss--asking member gap)))
    (concat (propertize (format "%s —%s" (org-truss-role-name (cadr gap))
                                (if (> (cddr gap) 1) (format " ×%d" (cddr gap)) ""))
                        'face 'org-truss-attention)
            (if asking (propertize (format " (%s)" asking) 'face 'org-truss-dim) ""))))

(defun org-truss--no-pattern-text (entry)
  "Return what the board says of ENTRY, (CHILD KIND . PARENT) of :no-pattern.
The role it plays, that PARENT has no pattern of KIND, and the patterns
that have the role, which PARENT is to take."
  (let* ((kind (cadr entry))
         (role (org-truss-member-role (car entry) kind))
         (ids (org-truss-patterns-with-role kind role)))
    (format "plays %s, but %s has no %s%s"
            (org-truss-role-name role) (org-truss-member-words (cddr entry)) kind
            (if ids
                (format "; %s has it" (mapconcat #'org-truss-pattern-label ids " or "))
              ""))))

(defun org-truss--structure-member-lines (model member prefix last path parent)
  "Return board lines for MEMBER of Structure and every member under it.
PREFIX draws the tree to the left; LAST says MEMBER ends its siblings.
PATH is the words from Structure down, which identifies the line across
redraws.  PARENT is the member above.  A member that comes below one its
apex member's telling pattern tells after is marked.  Where the output
document has its apex member's supporting members as a list, its words
open with the number, the bullet or the role the reader sees it with,
as any member's do.  Holding more than `org-truss-board-fold-limit', it
starts folded, and its line says how many it hides.  One whose words
are an include link alone is the member it includes, and names it
without a line under it, which would be its words again: as written,
with nothing more; as included, with what that member brings below its
line; see `org-truss--brought-lines'."
  (let* ((path (append path (list (org-truss-member-words member))))
         (inner (concat prefix (if last "  " "│ ")))
         (key (list 'structure path))
         (org-truss--whole (org-truss--whole-p key))
         (org-truss--telling member)
         (included (eq org-truss--order 'included))
         (stands-for (and included (org-truss--stands-for model member)))
         (stood-seen (and stands-for (org-truss--seen (cdr stands-for))))
         (brings (and stands-for (not stood-seen)))
         (includes (and (not (and (not included) (org-truss-include-alone-p member)))
                        (remove (car stands-for) (org-truss--included member))))
         (all (org-truss-member-supports member))
         (nested (+ (length (cdr (org-truss--subtree member))) (length includes)
                    (if brings (org-truss--brought-count model (cdr stands-for)) 0)))
         (folded (and (> nested 0)
                      (org-truss--folded-p key (org-truss--over-limit-p
                                                (+ (length all) (length includes))))))
         (supports (and (not folded) all))
         ;; Its text and links have the line to the members below run past.
         (stem (concat inner (if supports "│ " "  ")))
         (late (org-truss--late-text member parent))
         (stray (cadr (org-truss--no-role-p member)))
         (unheld (org-truss--no-pattern-p member))
         (why (string-join
               (delq nil (list (and stray
                                    (format "Plays no role of %s; %s gives it one"
                                            (org-truss-pattern-label (org-truss-member-pattern parent stray))
                                            (substitute-command-keys "\\[org-truss-board-roles]")))
                               (and unheld (let ((text (org-truss--no-pattern-text unheld)))
                                             (concat (upcase (substring text 0 1)) (substring text 1))))
                               late))
               ". "))
         (words (org-truss-member-words member))
         ;; It opens as the output document has it: an item of a list
         ;; with its bullet, a heading with no bullet.
         (form (and parent (org-truss-support-form parent member org-truss--in-list)))
         (listed (car form))
         (note (org-truss--grounds-note model member))
         (lines (org-truss--words-lines (org-truss--member-words member) (org-truss--opening form) note))
         (item (org-truss--member-item member :key key :fold key :nested nested
                                       :alone (and brings (org-truss-member-pos (cdr stands-for)))
                                       :names (org-truss--linked-positions model member (null includes))
                                       :folded (and (> nested 0) folded))))
    (append
     (list (org-truss--with-lane
            (org-truss--with-place
             (org-truss--line (concat prefix (if last "└ " "├ ")
                                      (org-truss--role-word model member)
                                      (if folded (org-truss--fold-mark nested) "")
                                      (if late (propertize " ⚠" 'face 'org-truss-attention) ""))
                              (car lines)
                              note
                              (append item (and (not (string-empty-p why)) (list :why why))))
             (org-truss--parts-text model words))
            (and stands-for (org-truss--lane-text model (cdr stands-for) stood-seen))))
     (org-truss--lines-under-words inner (cdr lines)
                                   (and org-truss--whole
                                        (org-truss--text-lines (org-truss-member-body member)
                                                               (org-truss-member-notes member)
                                                               (org-truss-noexport-p member)))
                                   item
                                   (and (not folded) (org-truss--pattern-line member inner item)) stem)
     (and (not folded) (org-truss--grounds-lines member stem (plist-get item :key)))
     ;; What it brings, stands on and includes is where it is in the
     ;; output document, an item when it is one.
     (let ((org-truss--in-list listed))
       (and (not folded)
            (append
             (and brings
                  (org-truss--brought-lines model (cdr stands-for) inner
                                            (list 'link path (car stands-for)) (car stands-for)))
             (and included
                  (org-truss--ground-members-lines model member (org-truss--ground-members model member)
                                                   stem (plist-get item :key)))
             (and includes (org-truss--includes-lines model member stem path (car stands-for))))))
     (let ((n (length supports)) (i 0) (org-truss--in-list listed))
       (mapcan (lambda (support)
                 (setq i (1+ i))
                 (org-truss--structure-member-lines model support inner (= i n) path member))
               supports))
     (and (not folded) (org-truss--gap-lines member (concat inner "  ") item)))))

(defun org-truss--check-heading (name)
  "Return the line that heads the check NAME, saying what it finds on hover."
  (org-truss--line (propertize (concat " " name) 'face 'org-truss-outline
                               'help-echo (org-truss-check-about name))))

(defun org-truss--check-line (model member key note)
  "Return the line naming MEMBER of MODEL under a check, keyed KEY.
Its board word on the left, its words in the middle, NOTE, what is wrong,
after them; RET on it goes to it.  A part is named by its part."
  (let ((part (org-truss-member-is-part member))
        (org-truss--whole (org-truss--whole-p key)))
    (org-truss--with-id
     (org-truss--line
      (concat "   " (if part
                        (capitalize (symbol-name (org-truss-member-part member)))
                      (org-truss--role-word model member)))
      (and (not part) (org-truss--member-words member))
      (and note (propertize note 'face 'org-truss-attention))
      (if part
          (list :type 'part :pos (org-truss-member-pos member) :part (org-truss-member-part member)
                :key key :fold key :nested 0)
        (org-truss--member-item member :key key :fold key :nested 0)))
     (and (not part) (not (org-truss-in-structure-p member)) (org-truss--id-text member)))))

(defun org-truss--check-group (model name entries note)
  "Return the lines of the check NAME for ENTRIES, or nil when there are none.
Each entry is (MEMBER . WHAT), and NOTE, given an entry, says what is
wrong there."
  (when entries
    (let ((i 0))
      (cons (org-truss--check-heading name)
            (mapcar (lambda (entry)
                      (org-truss--check-line model (car entry)
                                             (list name (org-truss-member-words (car entry))
                                                   (setq i (1+ i)))
                                             (funcall note entry)))
                    entries)))))

(defun org-truss--check-lines (model checks part)
  "Return the lines of what CHECKS finds in PART of MODEL, check by check.
Each thing is listed in the part it is found in, under the check that
finds it, as `org-truss-check-descriptions' names them."
  (let* ((in (lambda (entries) (seq-filter (lambda (e) (eq (org-truss-member-part (car e)) part))
                                           entries)))
         (ids (lambda (ids) (mapconcat (lambda (id) (format "[[%s]]" (org-truss--pointing-target id)))
                                       ids " ")))
         (broken (funcall in (plist-get checks :broken-links)))
         (found (funcall in (append (plist-get checks :broken-grounds)
                                    (plist-get checks :broken-sources)
                                    (mapcar (lambda (l) (cons (car l) (list 'loop (cdr l))))
                                            (plist-get checks :loops))
                                    (mapcan (lambda (id)
                                              (mapcar (lambda (m) (cons m (list 'duplicate id)))
                                                      (seq-filter (lambda (m) (equal (org-truss-member-id m) id))
                                                                  (org-truss-model-members model))))
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
                                      (format "#%s, which another member has too" (cadr (cdr e))))
                                     ((consp (cdr e))
                                      (format "%s includes it back" (org-truss--include-link (cadr (cdr e)))))
                                     ((string-prefix-p "[[" (cdr e)) (format "%s not found" (cdr e)))
                                     (t (format "%s not found" (funcall ids (list (cdr e)))))))))
                       (mapcar (lambda (b)
                                 (org-truss--line
                                  "   "
                                  (propertize (format "%s ← %s" (org-truss--include-link (cdr b))
                                                      (org-truss-member-words (car b)))
                                              'face 'org-truss-attention)
                                  nil (list :type 'broken :pos (org-truss-member-pos (car b))
                                            :link (cdr b) :holder (org-truss-member-pos (car b))
                                            :key (list 'broken (cdr b)))))
                               broken))))
           (org-truss--check-group
            model "No grounds" (funcall in (mapcar #'list (plist-get checks :no-grounds)))
            (lambda (_) org-truss-no-grounds-text))
           (org-truss--check-group
            model "Weak grounds" (funcall in (plist-get checks :weak-grounds))
            (lambda (e) (format "%s has no grounds" (funcall ids (list (cdr e))))))
           (org-truss--check-group
            model "Hidden grounds" (funcall in (plist-get checks :hidden-grounds))
            #'org-truss-hidden-ground-text)
           (org-truss--check-group
            model "Quotes not found" (funcall in (plist-get checks :quotes-not-found))
            #'org-truss-quote-not-found-text)
           (org-truss--check-group
            model "Grounds set low" (funcall in (plist-get checks :low-grounds))
            #'org-truss-grounds-set-low-text)
           (org-truss--check-group
            model "Mixed sources" (funcall in (plist-get checks :mixed-sources))
            (lambda (e) (format "points into %s" (string-join (cdr e) ", "))))
           (org-truss--check-group
            model "Sources in Situation" (funcall in (plist-get checks :situation-sources))
            #'org-truss-situation-sources-text)
           (org-truss--check-group
            model "Said again" (funcall in (plist-get checks :said-again))
            #'org-truss-said-again-text)
           (org-truss--check-group
            model "Not a heading" (funcall in (plist-get checks :unearned))
            #'org-truss-unearned-text)
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
                                (org-truss-pattern-label (org-truss-member-pattern (cddr e) (cadr e))))))
           (org-truss--check-group
            model "No pattern" (funcall in (plist-get checks :no-pattern))
            #'org-truss--no-pattern-text)
           (org-truss--check-group
            model "No relation" (funcall in (mapcar #'list (plist-get checks :no-relation)))
            (lambda (_) org-truss-no-relation-text))
           (org-truss--check-group
            model "Items and headings" (funcall in (plist-get checks :split))
            #'org-truss-split-text)
           (org-truss--check-group
            model "Out of order" (funcall in (plist-get checks :out-of-order))
            (lambda (e) (format "below %s" (org-truss-member-words (cdr e)))))
           (org-truss--check-group
            model "Words to write" (funcall in (mapcar #'list (plist-get checks :placeholders)))
            (lambda (_) org-truss-placeholder-text)))))
    (and lines (cons (org-truss--line "") lines))))

(defun org-truss--part-line (name gloss item)
  "Return the line that opens the part NAME on the board.
GLOSS says what is done there."
  (org-truss--line (concat " " (propertize name 'face 'org-truss-outline)
                           (propertize (concat "  " gloss) 'face 'org-truss-dim))
                   nil nil item))

(defun org-truss--part-lines (model part gloss)
  "Return the lines of PART of MODEL on the board: Brief, Subject or Message.
Its own line, with GLOSS, saying what is done there; the patterns it
names; its supporting members, each drawn as any member is; and a line
for each role its patterns ask for and none plays, on which a new member
plays it."
  (let* ((name (org-truss-member-part part))
         (item (list :type 'part :pos (org-truss-member-pos part)
                     :key (list 'part name) :part name)))
    (append
     (list (org-truss--part-line (capitalize (symbol-name name)) gloss item))
     (delq nil (list (org-truss--pattern-line part " " item)))
     (mapcan (lambda (m)
               (org-truss--member-lines model m "   " (list 'member (org-truss-member-words m))))
             (seq-remove #'org-truss--chained-p (org-truss-member-supports part)))
     (org-truss--gap-lines part "   " item))))

(defun org-truss--structure-lines (model)
  "Return Structure's tree for MODEL, as the output document has it."
  (let ((root (org-truss-model-structure model))
        (org-truss--in-structure t)
        (org-truss--shown (make-hash-table :test #'eq)))
    (if (null root)
        ;; A member read alone makes no output document, and is not missing one.
        (unless (org-truss-model-alone model)
          (list (org-truss--line (propertize " (no Structure part)" 'face 'org-truss-attention))))
      (let ((item (list :type 'part :pos (org-truss-member-pos root) :part 'structure
                        :key '(part structure)))
            (stem (if (org-truss-member-supports root) " │ " "   ")))
        ;; Structure's words name the part, as the other parts' do, and are
        ;; not in the output document; the board's word stands for them.
        (append
         ;; Its text is the output document's opening, drawn whole as a
         ;; member's is.
         (let ((org-truss--whole (org-truss--whole-p (plist-get item :key))))
           (cons (org-truss--part-line "Structure" "the output document's outline"
                                       (append item (list :fold (plist-get item :key) :nested 0)))
                 (org-truss--lines-under-words
                  " " nil
                  (and org-truss--whole
                       (org-truss--text-lines (org-truss-member-body root)
                                              (org-truss-member-notes root)))
                  item (org-truss--pattern-line root " " item) stem)))
         (org-truss--includes-lines model root stem '(root))
         (let* ((supports (org-truss-member-supports root)) (n (length supports)) (i 0))
           (mapcan (lambda (support)
                     (setq i (1+ i))
                     (org-truss--structure-member-lines model support " " (= i n) '(root) root))
                   supports))
         (org-truss--gap-lines root "   " item))))))

(defun org-truss--message-lines (model checks)
  "Return Message on the board for MODEL, then what is left to do there.
Drawn as Brief and Subject are.  On the board of one heading of a file
that is no truss file, that member, as a part of its own."
  (let ((alone (org-truss-model-alone model))
        (message (org-truss-model-message model)))
    (append
     (cond (alone
            (cons (org-truss--line "")
                  (cons (org-truss--part-line "Heading" "one heading, read as a member of Message"
                                              (list :type 'part :pos (org-truss-member-pos alone)
                                                    :part 'message :key '(part message)))
                        (org-truss--member-lines model alone "   "
                                                 (list 'member (org-truss-member-words alone))))))
           (message
            (cons (org-truss--line "") (org-truss--part-lines model message "what the output document says"))))
     (org-truss--check-lines model checks 'message))))

(defun org-truss--board-lines (model)
  "Return the board for MODEL as a list of lines.
Under the title come the four parts, in the order the work is done in:
Brief, what the output document must satisfy; Subject, the facts found;
Message, what the output document says; Structure, its outline.  Each is
followed by what is left to do there.  What all of it is drawn from --
`org-truss--uses', `org-truss--in-document', `org-truss--checks' and
`org-truss--chained' -- is bound for it by `org-truss-board-text'."
  (let* ((org-truss--model model)
         (checks org-truss--checks)
         (brief (org-truss-model-brief model))
         (subject (org-truss-model-subject model)))
    (append (org-truss--head-lines model)
            (and brief
                 (append (list (org-truss--line ""))
                         (org-truss--part-lines model brief "what the output document must satisfy")
                         (org-truss--check-lines model checks 'brief)))
            (and subject
                 (append (list (org-truss--line ""))
                         (org-truss--part-lines model subject "the facts found")
                         (org-truss--check-lines model checks 'subject)))
            (org-truss--message-lines model checks)
            (list (org-truss--line ""))
            (org-truss--structure-lines model)
            (org-truss--check-lines model checks 'structure))))

(defun org-truss--head-lines (model)
  "Return the head of the board for MODEL: the title.
The title the output document is written under, the file's #+title,
its links read; see `org-truss-document-title'."
  (let ((title (org-truss-document-title model))
        (pos (alist-get '(title) (org-truss-model-locations model) nil nil #'equal)))
    (list (org-truss--line
           (concat " Title" (if (buffer-modified-p (org-truss-model-buffer model))
                                (propertize "  unsaved" 'face 'org-truss-attention)
                              ""))
           (propertize (org-truss--link-text (or title "")) 'face 'org-truss-outline)
           nil
           (and pos (list :type 'part :pos pos :key '(part title)))))))

(defun org-truss--column (lines)
  "Return the column the middle starts at on LINES.
Four past the widest of the board's own words, with the marks before
the middle, on a line that has any, so two dots lead from each to the
middle, not to be read as the one between two roles; see
`org-truss--marks-text'."
  (+ 4 (seq-reduce (lambda (widest line)
                     (let ((marks (org-truss--marks-text line)))
                       (if (or marks (plist-get line :middle))
                           (max widest (+ (string-width (plist-get line :left))
                                          (if marks (1+ (string-width marks)) 0)))
                         widest)))
                   lines 0)))

(defun org-truss--owner (key)
  "Return the key of the line that the line keyed KEY is drawn for.
The lines a member's line takes below it -- the rest of its text, the
line naming its patterns, a line its words are broken onto -- are its
own; any other line is its own owner."
  (pcase (last key 2)
    (`(,(or 'text 'wrap) ,(pred integerp)) (butlast key 2))
    (`(,_ pattern) (butlast key))
    (_ key)))

(defun org-truss--model-directory (model)
  "Return the directory the truss file of MODEL is in."
  (with-current-buffer (org-truss-model-buffer model)
    (if buffer-file-name (file-name-directory buffer-file-name) default-directory)))

(defun org-truss-board-text (model &optional entries width)
  "Return the board for MODEL as a string, every line whole when ENTRIES.
Else a line is folded, open or whole as `org-truss--folding' says.  The
middle starts one column for every line, right after the marks before
it; see `org-truss--column'.  WIDTH is that of the window the board is drawn
for: the middle has it from that column to its edge, and a line drawn
whole is broken to fit; see `org-truss-board-middle-width'.

What the board is drawn from is worked out once and bound for the
drawing: how each member is used, what the output document has, what
the checks find, what Structure brings, and the sources quotes are
looked for in, each read once."
  (let* ((org-truss--uses (org-truss--member-uses model))
         (org-truss--in-document (org-truss-in-document model))
         (org-truss--source-texts (make-hash-table :test #'equal))
         (org-truss--checks (org-truss-checks model))
         (org-truss--chained (and (eq org-truss--order 'included) (org-truss--chain model)))
         (org-truss--base-directory (org-truss--model-directory model))
         (whole (or entries (rassq 'whole org-truss--folding)))
         ;; Where the middle starts does not depend on what is drawn whole,
         ;; so the drawing on one line each says it.  With nothing drawn
         ;; whole, that drawing is the board.
         (one-line (let ((org-truss--folding
                          (mapcar (lambda (fold) (if (eq (cdr fold) 'whole) (cons (car fold) 'open) fold))
                                  org-truss--folding)))
                     (org-truss--board-lines model)))
         (column (org-truss--column one-line))
         (org-truss--middle-width
          (cond (org-truss-board-middle-width)
                (width (max 20 (- width 1 column)))
                (t 80)))
         (org-truss--middle-column column)
         (lines (if (not whole)
                    one-line
                  (mapcan (lambda (line) (if (plist-get line :whole) (org-truss--whole-lines line) (list line)))
                          (let ((org-truss--all-whole entries))
                            (org-truss--board-lines model))))))
    (mapconcat (lambda (line) (org-truss--lay-out line column)) lines "")))

(provide 'org-truss-draw)

;;; org-truss-draw.el ends here

;;; org-truss-board.el --- The board: a truss file drawn as a structure  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The board draws the structure with the members each section shows, and
;; under it what is left undone.  It is read-only: its commands change the
;; truss file and draw the board again.  Writing happens in the file; RET
;; goes there.
;;
;; The board's own words are English whatever `org-truss-language' says, so
;; a label, a heading or a title in another language is plainly the file's.

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

(defface org-truss-branch '((t :inherit org-truss-dim))
  "Face for the tree that joins a member to the members nested under it.
The tree of the brief's fields and of the sections keeps the default face,
so the two trees read apart where they meet."
  :group 'org-truss)

;; Every line has three columns.  On the left is what the board says the
;; line is, in its own words.  From one column, shared by every line, the
;; file's words -- headings, labels, the title -- as written.  On the right,
;; what the reader sees of it, so the document can be read down the page.
;; What the board says about how a section or an argument is arranged -- the
;; pattern it follows -- goes on the line below, so the left side stays
;; narrow and the file's words stay close to the tree.  With entry text
;; shown, what is written under each heading follows its line: what stays in
;; the file under the file's words, the rest of what the reader sees on the
;; right; the pattern stays right under the heading's line, beside them.

(defcustom org-truss-board-heading-width nil
  "Width the board gives the file's words on a line before what the reader sees.
The file's words all start in one column, just right of the widest of the
board's own words; what the reader sees starts this far right of that
column.  Nil gives the file's words half of the window right of that
column, never less than 20, so they and what the reader sees share it
evenly; a number fixes it.  File's words too long for the room are cut
short, the whole of them in the tooltip, and entry text is broken to fit
it."
  :type '(choice (const :tag "Half of the window" nil) integer)
  :group 'org-truss)

(defcustom org-truss-board-reader-width nil
  "Width at which entry text breaks what the reader sees.
Nil fits it to the window, from where that column starts to the window's
edge, never narrower than 20 columns; a number fixes it.  Without entry
text nothing is broken: a line runs on and the window cuts it."
  :type '(choice (const :tag "Fit the window" nil) integer)
  :group 'org-truss)

(defcustom org-truss-board-fold-limit 5
  "How many members a field of the brief or the subject shows before folding.
A field holding more starts folded on the board, as one line that says how
many it holds; \\<org-truss-board-mode-map>\\[org-truss-board-fold] unfolds it."
  :type 'integer
  :group 'org-truss)

(defvar-local org-truss--folds nil
  "Lines of this board folded or unfolded by hand, as (KEY . open|closed).
A line not here is folded or not as `org-truss-board-fold-limit' says.")

(defvar org-truss--folding nil
  "The folds of the board being drawn; see `org-truss--folds'.")

(defun org-truss--folded-p (key default)
  "Non-nil when the line whose fold is KEY is folded; DEFAULT if not toggled."
  (let ((state (assoc key org-truss--folding)))
    (if state (eq (cdr state) 'closed) default)))

(defun org-truss--fold-mark (n)
  "Return what a folded line shows of the N members it hides."
  (propertize (format " ▸%d" n) 'face 'org-truss-dim))

(defvar org-truss--heading-width 40
  "Width given the file's words, while a board is drawn.")

(defvar org-truss--reader-width 60
  "Width entry text breaks what the reader sees at, while a board is drawn.")

(defvar-local org-truss--drawn-width nil
  "Width of the window the board was drawn for.")

(defvar-local org-truss--source nil
  "The truss file buffer this board draws.")

(defvar-local org-truss--file nil
  "The truss file this board draws, to visit again if its buffer is killed.")

(defvar-local org-truss--drawn-tick nil
  "The source buffer's text tick when the board was drawn.
`buffer-chars-modified-tick', which counts changes to the text only.  A
change to text properties alone -- fontification, which runs whenever the
file is shown -- moves no position the board holds, and must not make the
board think the file was edited.")

(defvar-local org-truss--entry-text nil
  "Non-nil when this board shows the text under each heading.")

(defvar-local org-truss--wraps nil
  "Keys of the lines of this board drawn the other way from the rest.
Whole, with the text under the heading, while entry text is hidden; on one
line while it is shown.")

(defvar org-truss--wrapping nil
  "The lines of the board being drawn the other way; see `org-truss--wraps'.")

(defvar org-truss--text-column 0
  "The column the file's words start at, while a board is drawn with entry text.")

(defvar-local org-truss--view nil
  "The buffer showing this board's document, if one has been opened.")

(defvar org-truss--entries nil
  "Non-nil while a board is drawn with the text under each heading.")

(defvar org-truss--told nil
  "Non-nil while the structure is drawn.
There a line's right says what the document tells of it, and a member
brings only what the document tells with it: not its grounds, nor what
its pattern still asks for, nor, for a member of the subject, its parts.
Elsewhere a line's right says where the member is used.")

(defvar org-truss--uses nil
  "While a board is drawn, how each member is used, by the member.
\(SECTIONS . MEMBERS): the sections that list it, and the members it is a
ground of, each in the order of the file.")

;;;; Drawing

(defun org-truss--line (left &optional text note item)
  "Return one board line, laid out later by `org-truss-board-text'.
LEFT is what the board says the line is.  TEXT is the file's words for it,
NOTE what the board notes about it.  ITEM is what the line stands for, kept
as a text property for the commands; its :why, if any, is the line's help."
  (list :left left :text text
        :note (and note (not (string-empty-p note)) note)
        :item item))

(defun org-truss--leader (width)
  "Return WIDTH columns that lead the eye from the board's words to the file's.
A space at each end; dots between, when there is room for one."
  (let ((dots (/ (- width 2) (char-width ?·))))
    (if (< dots 1)
        (make-string width ?\s)
      (concat " " (propertize (make-string dots ?·) 'face 'org-truss-dim)
              (make-string (- width 1 (* dots (char-width ?·))) ?\s)))))

(defun org-truss--lay-out (line column)
  "Return LINE as text, with its file's words starting at COLUMN.
When something follows them on the right, the file's words are cut short
to leave it its column."
  (let* ((left (plist-get line :left))
         (note (plist-get line :note))
         (room (- org-truss--heading-width 2))
         (text (let ((text (plist-get line :text)))
                 (if (and note text (> (string-width text) room))
                     (propertize (truncate-string-to-width text room nil nil "…")
                                 'help-echo text)
                   text)))
         (why (plist-get (plist-get line :item) :why))
         (gap (- column (string-width left)))
         (out (if (and text (or note (not (string-empty-p text))))
                  (concat left
                          (if (or (plist-get line :bare) (string-blank-p left))
                              (make-string gap ?\s)
                            (org-truss--leader gap))
                          text)
                left)))
    (when note
      (setq out (concat out
                        (make-string (max 2 (- (+ column org-truss--heading-width)
                                               (string-width out)))
                                     ?\s)
                        note)))
    (setq out (propertize (concat out "\n") 'org-truss-item (plist-get line :item)))
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
  (let* ((kind (org-truss-kind model member))
         (face (cond ((or (org-truss-hypothesis-p model member) (eq kind 'assumption)
                          (and (eq kind 'summary) (org-truss--rests-on-open-p model member nil)))
                      'org-truss-tentative)
                     ((or (memq kind '(bare question))
                          (and (eq kind 'objection) (org-truss-unanswered-p model member)))
                      'org-truss-attention))))
    (propertize (if (org-truss-hypothesis-p model member) "hypothesis" (symbol-name kind))
                'face face)))

(defun org-truss--link-text (text)
  "Return TEXT with each link read as its description, or else its target."
  (replace-regexp-in-string
   "\\[\\[\\*?\\([^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?\\]"
   (lambda (link) (or (match-string 2 link) (match-string 1 link)))
   text t t))

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
descriptions, and a blank line stays between paragraphs."
  (let (out)
    (dolist (para (split-string (string-trim (org-truss--link-text text)) "\n[ \t]*\n" t))
      (when out (push "" out))
      (let ((lines (split-string para "\n")))
        (dolist (line (if (seq-some (lambda (l)
                                      (string-match-p "\\`[ \t]*\\(|\\|#\\+\\|[-+] \\|[0-9]+[.)] \\)" l))
                                    lines)
                          (mapcan (lambda (l)
                                    (if (string-match-p "\\`[ \t]*|" l)
                                        (list (truncate-string-to-width l width))
                                      (org-truss--break l width)))
                                  lines)
                        (org-truss--break (org-truss--one-line para) width)))
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
  (if (not org-truss--entries)
      (list (org-truss--reader-text seen))
    (let ((title (car seen))
          (body (mapcar (lambda (line) (propertize line 'face 'org-truss-dim))
                        (org-truss--fill (or (cdr seen) "") org-truss--reader-width))))
      (if (and title (not (string-blank-p title)))
          (append (org-truss--break (propertize title 'face 'org-truss-reader)
                                    org-truss--reader-width)
                  body)
        body))))

(defun org-truss--member-reader (member &optional wording)
  "Return what the reader sees of MEMBER as lines, the first for its own line.
WORDING when a section tells it in words of its own; else its public block,
or its label; `noexport' when the reader sees nothing of it.  Whom to
confirm it with, when the file says, follows the first line, or with entry
text, the last, on lines of its own."
  (let ((lines (cond ((org-truss-noexport-p member)
                      (list (propertize "noexport" 'face 'org-truss-dim)))
                     (wording (org-truss--reader-lines (cons nil wording)))
                     (t (org-truss--reader-lines (org-truss-member-shown member)))))
        (confirm (and (org-truss-member-confirm member)
                      (propertize (concat "confirm with " (org-truss-member-confirm member))
                                  'face 'org-truss-attention))))
    (cond ((null confirm) lines)
          (org-truss--entries
           (append lines (org-truss--break confirm org-truss--reader-width)))
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

(defun org-truss--member-words (member)
  "Return MEMBER's heading as the board draws it: in the face the file gives
a heading of its level.  The board colours it itself, rather than copy the
file's, which is there only where the file has been shown."
  (propertize (org-truss-member-label member)
              'face (org-truss--level-face (org-truss-member-level member))))

(defun org-truss--label-lines (label)
  "Return LABEL as the lines it is drawn on.
One, cut short if need be; while entry text is shown, as many as it takes
to break it to the room of the file's column, since the board is then read
rather than scanned."
  (if org-truss--entries
      (org-truss--break label (- org-truss--heading-width 2))
    (list label)))

(defun org-truss--entry-lines (left more notes below item &optional head stem)
  "Return the lines under a heading's own line on the board.
HEAD, if any, is the line that says how what is under the heading is
arranged.  When the board shows entry text, MORE, the rest of the
heading's own words, and then NOTES, what is written under the heading and
stays in the file, go in the file's column; BELOW, the rest of what the
reader sees, on the right.  LEFT starts each line, and STEM, when given,
each line below HEAD, or every line without one: the line of the tree down
to what branches off under the heading.  ITEM is the heading's line's,
kept under a key of its own.

HEAD's words take the left of the first of these lines, so they stay right
under the heading's line.  When they are too wide for the board's own
column they take the line after the heading's own words instead, and the
file's column leaves that line to them."
  (if (not org-truss--entries)
      (and head (list head))
    (let* ((notes (mapcar (lambda (line) (propertize line 'face 'org-truss-dim))
                          (org-truss--fill (or notes "") (- org-truss--heading-width 2))))
           (wide (and head (> (+ (string-width (plist-get head :left)) 2)
                              org-truss--text-column)))
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

(defun org-truss--wrapped (line)
  "Return LINE as the lines it takes while entry text is shown.
Its file's words are broken to their column and what follows them to the
reader's, and what does not fit goes on lines of its own below, which
start with LINE's :under, the tree on its left going on down.  A heading
and what the reader sees of it are broken where they are drawn, to keep
them in order with what is under the heading; this breaks the rest: a
ground, what a check lists."
  (let* ((room (- org-truss--heading-width 2))
         (text (plist-get line :text))
         (note (plist-get line :note))
         (texts (and text (org-truss--break text room)))
         (notes (and note (org-truss--break note org-truss--reader-width)))
         (item (plist-get line :item)))
    (if (and (null (cdr texts)) (null (cdr notes)))
        (list line)
      (cons (plist-put (plist-put (copy-sequence line) :text (car texts)) :note (car notes))
            (cl-loop for i from 1 below (max (length texts) (length notes))
                     collect (append (org-truss--line
                                      (or (plist-get line :under) "")
                                      (or (nth i texts) "") (nth i notes)
                                      (and item
                                           (plist-put (copy-sequence item) :key
                                                      (append (plist-get item :key)
                                                              (list 'wrap i)))))
                                     '(:bare t)))))))

(defvar org-truss--model nil
  "The model of the board being drawn.")

(defvar org-truss--checks nil
  "What `org-truss-checks' says of the board being drawn.")

(defun org-truss--section-name (section)
  "Return SECTION as the board names it where a member is used.
Its public title, or its heading; the root is the Structure."
  (let ((public (car (org-truss-section-public section))))
    (cond ((eq section (org-truss-model-structure org-truss--model)) "Structure")
          ((and public (not (string-blank-p public))) public)
          (t (org-truss-section-label section)))))

(defun org-truss--use-text (member)
  "Return where MEMBER is used, for the right of its line outside the structure.
The sections that list it, after an arrow; else the first member it is a
ground of, and how many more.  Nil when nothing uses it itself."
  (let* ((use (and org-truss--uses (gethash member org-truss--uses)))
         (sections (car use))
         (members (cdr use)))
    (cond (sections
           (propertize (concat "→ " (mapconcat #'org-truss--section-name sections ", "))
                       'face 'org-truss-dim))
          (members
           (propertize (format "ground of %s%s" (org-truss-member-label (car members))
                               (if (cdr members) (format " +%d" (length (cdr members))) ""))
                       'face 'org-truss-dim)))))

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

(defun org-truss--member-lines (model member indent key
                                      &optional link section marker wording)
  "Return board lines for MEMBER and what is nested under it.
INDENT starts each line: a string, or a cons (LINE . UNDER) for a member
nested under another, LINE starting its own line and UNDER the lines under
it, as `org-truss--branch' makes them.  The members nested under MEMBER
branch off right under it, as the sections of the structure do; its
pattern heads them, and its grounds go in further, as a section's links do.
KEY identifies the line across redraws.  LINK,
the reference the section's link makes, and SECTION are set when a
section lists MEMBER, so the line can be moved;
WORDING, when that section tells it in words of its own.  MARKER, when
MEMBER says how to do the member above it, is how the reader sees it
begin: its number, its bullet, its label.

In the structure, `org-truss--told', the right is what the document tells
of it, and only what the document tells comes with it.  Elsewhere the
right is where it is used, and its grounds follow it, marked with an
arrow, and the places its pattern asks for and it lacks."
  (let* ((under (if (consp indent) (cdr indent) indent))
         (indent (if (consp indent) (car indent) indent))
         (told org-truss--told)
         (material (org-truss-material-p member))
         ;; A cluster always says what it is, written or not: with nothing
         ;; written, what is under it is its support, why › reasons.
         (patterned (or (org-truss-member-logic member) (org-truss-member-telling member)
                        (org-truss-member-children member)))
         (role (org-truss-member-role member))
         (label (org-truss--label-lines (org-truss--member-words member)))
         ;; A marker opens the first line, and the lines after it are
         ;; indented as far, as a list item's are.
         (hang (if (and told marker) (string-width marker) 0))
         (reader (cond (told
                        (let ((org-truss--reader-width (- org-truss--reader-width hang)))
                          (org-truss--member-reader member wording)))
                       ((and org-truss--entries (org-truss--use-text member))
                        (org-truss--break (org-truss--use-text member) org-truss--reader-width))
                       (t (list (org-truss--use-text member)))))
         (reader (if (and told marker (car reader))
                     (cons (concat marker (car reader))
                           (mapcar (lambda (line)
                                     (if (string-empty-p line) line
                                       (concat (make-string hang ?\s) line)))
                                   (cdr reader)))
                   reader))
         (how (org-truss-how-children member))
         (n 0)
         (children (and (not (and told material)) (org-truss-member-children member)))
         (nested (length (mapcan #'org-truss--subtree children)))
         (folded (and (> nested 0) (org-truss--folded-p key nil)))
         (shown (and (not folded) children))
         ;; What comes between its pattern and the members branching off
         ;; below -- its notes, its grounds -- has the tree's line run past.
         (stem (concat under (if shown (propertize "│ " 'face 'org-truss-branch) "  ")))
         (item (append (list :type 'member :pos (org-truss-member-pos member)
                             :label (org-truss-member-label member)
                             :link link :section section :key key)
                       (and (> nested 0) (list :fold key :folded folded)))))
    (append
     (list (org-truss--line
            (concat indent
                    (if (org-truss-against-p member) "x " "")
                    (org-truss--kind-word model member)
                    (if folded (org-truss--fold-mark nested) "")
                    (if role
                        (propertize (format "  [%s]" (org-truss-role-name role)) 'face 'org-truss-dim)
                      ""))
            (car label)
            (car reader)
            item))
     (org-truss--entry-lines
      under (cdr label) (org-truss-member-notes member) (cdr reader) item
      (and patterned (not folded) (not (and told material))
           (org-truss--line
            (concat under
                    (propertize (if material
                                    (format "(%s)"
                                            (org-truss-pattern-label (org-truss-member-logic member)))
                                  (format "(%s, %s)"
                                          (org-truss-pattern-label (org-truss-member-logic member))
                                          (org-truss-pattern-name
                                           (org-truss-conclusion-position member))))
                                'face 'org-truss-dim
                                'help-echo (and (null (org-truss-member-logic member))
                                                (substitute-command-keys
                                                 "No TRUSS_LOGIC is written, so what is under it is its support; \\[org-truss-board-pattern] writes one"))))
            nil nil (list :type 'member :pos (org-truss-member-pos member)
                          :key (append key '(pattern)))))
      stem)
     (mapcar (lambda (ref)
               (let ((ground (org-truss-member-by-ref model ref)))
                 (append
                  (org-truss--line
                   (concat stem (propertize "⬑ " 'face 'org-truss-dim)
                           (if ground (org-truss--kind-word model ground)
                             (propertize "broken ground" 'face 'org-truss-attention)))
                   (propertize (if ground (org-truss-member-label ground)
                                 (format "[[%s]]" (org-truss--target ref)))
                               'face 'org-truss-dim)
                   nil (list :type 'member :pos (org-truss-member-pos (or ground member))
                             :label (and ground (org-truss-member-label ground))
                             :claim (org-truss-member-pos member) :ground ref
                             :key (append key (list 'ground ref))))
                  (list :under stem))))
             (and (not told) (not folded) (org-truss-member-grounds member)))
     (let ((i 0))
       (mapcan (lambda (child)
                 (org-truss--member-lines model child
                                          (org-truss--branch under (= (setq i (1+ i))
                                                                      (length shown)))
                                          (append key (list (org-truss-member-label child)))
                                          nil nil
                                          (and told
                                               (memq child how)
                                               (not (org-truss-noexport-p child))
                                               (let ((marker (org-truss--list-marker
                                                              member child (setq n (1+ n)))))
                                                 (concat (car marker) (cdr marker))))))
               shown))
     (mapcar (lambda (gap)
               (org-truss--line
                (concat under "  "
                        (propertize (format "%s —%s" (org-truss-role-name (car gap))
                                            (if (> (cdr gap) 1) (format " ×%d" (cdr gap)) ""))
                                    'face 'org-truss-attention))
                nil nil (list :type 'member :pos (org-truss-member-pos member)
                              :gap (car gap)
                              :key (append key (list 'gap (car gap))))))
             (and (not told) (not folded) (org-truss-gaps member))))))

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
It fits when it shares questions with exactly one of PATTERN's places.  A
section that answers nothing is not judged here: its own line says so."
  (let* ((slots (plist-get (org-truss-pattern pattern) :slots))
         (hits (mapcar #'car (seq-filter (lambda (slot) (seq-intersection roles (nthcdr 2 slot)))
                                         slots))))
    (cond ((or (null roles) (null slots) (= (length hits) 1)) nil)
          ((null hits) (format "no place for %s in %s"
                               (org-truss-role-names roles) (org-truss-pattern-name pattern)))
          (t (format "fits more than one place: %s"
                     (concat (string-join (butlast hits) ", ") " and " (car (last hits))))))))

(defun org-truss--pattern-line (section indent item)
  "Return the line naming the patterns SECTION follows, or nil if it follows none.
Its logic pattern -- what the sections below must answer, how › proposal --
and its telling pattern, which arranges them.  It goes under SECTION's own
line, at INDENT.  ITEM is SECTION's line's, kept under a key of its own."
  (let ((names (delq nil (mapcar (lambda (id) (and id (org-truss-pattern-label id)))
                                 (list (org-truss-section-logic section)
                                       (org-truss-section-telling section))))))
    (and names
         (org-truss--line
          (concat indent (propertize (format "(%s)" (string-join names ", "))
                                     'face 'org-truss-dim))
          nil nil (plist-put (copy-sequence item) :key
                             (append (plist-get item :key) '(pattern)))))))

(defun org-truss--section-gap-lines (section indent item)
  "Return a line for each role SECTION's patterns ask for and nothing right
below answers, at INDENT; ITEM is SECTION's line's.  On one, a new section
answers that role."
  (mapcar (lambda (gap)
            (org-truss--line
             (concat indent
                     (propertize (format "%s —%s" (org-truss-role-name (car gap))
                                         (if (> (cdr gap) 1) (format " ×%d" (cdr gap)) ""))
                                 'face 'org-truss-attention))
             nil nil (append (list :gap (car gap)
                                   :key (append (plist-get item :key) (list 'gap (car gap))))
                             item)))
          (cdr (assq section (plist-get org-truss--checks :section-gaps)))))

(defun org-truss--section-lines (model section prefix last path parent-pattern)
  "Return board lines for SECTION and the sections below it.
PREFIX draws the tree to the left; LAST says SECTION ends its siblings.
PATH is the labels from the root, which identifies the line across redraws."
  (let* ((path (append path (list (org-truss-section-label section))))
         (inner (concat prefix (if last "  " "│ ")))
         (children (org-truss-section-children section))
         ;; Its notes and links have the line to the sections below run past.
         (stem (concat inner (if children "│ " "  ")))
         (roles (org-truss-section-roles section))
         (misfit (and parent-pattern (org-truss--misfit roles parent-pattern)))
         (public (org-truss-section-public section))
         (title (if (and (car public) (not (string-blank-p (car public))))
                    (car public)
                  (org-truss-section-label section)))
         (unnamed (and parent-pattern (org-truss-slot-name-p parent-pattern title)
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
                                    (if roles (org-truss-role-names roles)
                                      (propertize "no role" 'face 'org-truss-attention))
                                    (if misfit (propertize " ⚠" 'face 'org-truss-attention) ""))
                            (car label)
                            (car reader)
                            (append item (list :why (and (or misfit unnamed)
                                                               (string-join (delq nil (list misfit unnamed))
                                                                            ". "))))))
     (org-truss--entry-lines inner (cdr label) (org-truss-section-notes section) (cdr reader) item
                             (org-truss--pattern-line section inner item) stem)
     (org-truss--links-lines model section stem path)
     (let ((n (length children)) (i 0))
       (mapcan (lambda (child)
                 (setq i (1+ i))
                 (org-truss--section-lines model child inner (= i n) path
                                           (org-truss-section-telling section)))
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
                    (org-truss--line
                     (concat "   " (org-truss--kind-word model m))
                     (org-truss--member-words m)
                     (if right
                         (funcall right m)
                       (car (let ((org-truss--entries nil)) (org-truss--member-reader m))))
                     (list :type 'member :pos (org-truss-member-pos m)
                           :label (org-truss-member-label m) :unplaced (eq kind 'unplaced)
                           :key (list kind (org-truss-member-label m)))))
                  members))))

(defconst org-truss--board-fields
  '(((brief reader) "Reader" t)
    ((brief question) "Their question" t)
    ((brief response) "Response wanted")
    ((brief constraints) "Document constraints")
    ((subject premises) "Premises")
    ((subject issue) "Issue" t)
    ((subject constraints) "Constraints"))
  "The fields of the brief and the subject drawn on the board.
Each with the board's word for it.  Those marked t are drawn even while
empty, as a reminder; the rest once they hold text or members.")

(defun org-truss--field-text (model key)
  "Return the text of the field KEY, (PART FIELD), of MODEL as lines, or nil.
One line; while entry text is shown, as many as it takes to break it to
the room of the file's column."
  (let ((text (alist-get (cadr key) (if (eq (car key) 'brief)
                                        (org-truss-model-brief model)
                                      (org-truss-model-subject model)))))
    (and text (not (string-empty-p text))
         (mapcar (lambda (line) (propertize line 'face 'org-truss-dim))
                 (if org-truss--entries
                     (org-truss--fill text (- org-truss--heading-width 2))
                   (list (org-truss--one-line text)))))))

(defun org-truss--field-members (model key)
  "Return the members written under the field KEY of MODEL."
  (alist-get key (org-truss-model-conditions model) nil nil #'equal))

(defun org-truss--field-drawn-p (model field at)
  "Non-nil when FIELD, an entry of `org-truss--board-fields', is on the board.
It is when the file has it and it is marked to be drawn, or holds something."
  (let ((key (car field)))
    (and (funcall at key)
         (or (nth 2 field) (org-truss--field-text model key)
             (org-truss--field-members model key)))))

(defun org-truss--field-lines (model field at prefix inner)
  "Return board lines for FIELD, an entry of `org-truss--board-fields', of MODEL.
Its own line, PREFIX and its name, with its text, and with entry text the
rest of its text below, from INNER; then the members written under it, so
they can be gone to and placed from here.  AT gives the item for a place
in the file."
  (let* ((key (car field))
         (text (org-truss--field-text model key))
         (members (org-truss--field-members model key))
         (fold (list 'field key))
         (folded (and members (org-truss--folded-p
                               fold (> (length members) org-truss-board-fold-limit))))
         (item (append (funcall at key)
                       (and members (list :fold fold :folded folded)))))
    (and (org-truss--field-drawn-p model field at)
         (append (list (org-truss--line (concat prefix (nth 1 field)
                                                (if folded (org-truss--fold-mark (length members)) ""))
                                        (car text) nil item))
                 (org-truss--entry-lines inner (cdr text) nil nil item)
                 (and (not folded)
                      (mapcan (lambda (m)
                                (org-truss--member-lines model m (concat inner "  ")
                                                         (list 'field key (org-truss-member-label m))))
                              members))))))

(defun org-truss--part-line (name gloss item &optional reader)
  "Return the line that opens the part NAME on the board.
GLOSS says what is done there; READER, what the document opens with."
  (org-truss--line (concat " " (propertize name 'face 'org-truss-section)
                           (propertize (concat "  " gloss) 'face 'org-truss-dim))
                   nil reader item))

(defun org-truss--subject-lines (model at)
  "Return the subject's part of the board for MODEL: its fields, as a tree.
AT gives the item for a place in the file."
  (let* ((fields (seq-filter (lambda (field)
                               (and (eq (caar field) 'subject)
                                    (org-truss--field-drawn-p model field at)))
                             org-truss--board-fields))
         (n (length fields))
         (i 0))
    (mapcan (lambda (field)
              (let ((last (= (setq i (1+ i)) n)))
                (org-truss--field-lines model field at (if last " └ " " ├ ")
                                        (if last "   " " │ "))))
            fields)))

(defun org-truss--structure-lines (model)
  "Return the structure's tree for MODEL, as the document tells it."
  (let ((root (org-truss-model-structure model))
        (org-truss--told t))
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
            (org-truss--entry-lines " " nil (org-truss-section-notes root) (cdr lead) item
                                    (org-truss--pattern-line root " " item) stem)))
         (org-truss--links-lines model root stem '(root))
         (let* ((children (org-truss-section-children root)) (n (length children)) (i 0))
           (mapcan (lambda (child)
                     (setq i (1+ i))
                     (org-truss--section-lines model child " " (= i n) '(root)
                                               (org-truss-section-telling root)))
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
         (checks (org-truss-checks model))
         (org-truss--checks checks)
         (source (org-truss-model-buffer model))
         (places (org-truss-model-places model))
         (at (lambda (key)
               (let ((pos (alist-get key places nil nil #'equal)))
                 (and pos (list :type 'brief :pos pos :key (cons 'brief key)
                                :field (and (cdr key) key))))))
         (members-pos (with-current-buffer source
                        (org-with-wide-buffer (org-truss--part-pos "members"))))
         (material (lambda (ms) (seq-filter #'org-truss-material-p ms)))
         (argued (lambda (ms) (seq-remove #'org-truss-material-p ms)))
         (misplaced (plist-get checks :misplaced))
         (why (lambda (m) (propertize (cdr (assq m misplaced)) 'face 'org-truss-attention)))
         (gaps (mapcar #'car (plist-get checks :gaps))))
    (append
     (let ((title (org-truss-model-title model)))
       (list (org-truss--line
              (concat " Title" (if (buffer-modified-p source)
                                   (propertize "  unsaved" 'face 'org-truss-attention)
                                 ""))
              (propertize (or title "") 'face 'org-truss-section)
              (and title (propertize title 'face 'org-truss-reader))
              (funcall at '(title)))))
     (mapcan (lambda (field) (org-truss--field-lines model field at " " " "))
             (seq-filter (lambda (field) (eq (caar field) 'brief)) org-truss--board-fields))
     (let ((item (funcall at '(subject))))
       (and item
            (cons (org-truss--line "")
                  (cons (org-truss--part-line "Subject" "what was found: facts, summed up in clusters"
                                              (append item '(:part subject)))
                        (org-truss--subject-lines model at)))))
     (org-truss--list-lines model "Unmet constraints" (plist-get checks :unmet) 'unmet)
     (org-truss--list-lines model "No source" (funcall material (plist-get checks :bare)) 'unsourced)
     (org-truss--list-lines model "Open questions" (funcall material (plist-get checks :questions))
                            'subject-questions)
     (org-truss--list-lines model "Assumptions" (funcall material (plist-get checks :assumptions))
                            'subject-assumptions)
     (org-truss--list-lines model "Pattern gaps" (funcall material gaps) 'subject-gaps)
     (org-truss--list-lines model "Misplaced" (funcall material (mapcar #'car misplaced))
                            'subject-misplaced why)
     (and members-pos
          (append
           (list (org-truss--line "")
                 (org-truss--part-line "Members" "what is made of it: interpretations and decisions"
                                       (list :type 'brief :pos members-pos :part 'members
                                             :key '(brief (members)))))
           (mapcan (lambda (m)
                     (org-truss--member-lines model m "   " (list 'member (org-truss-member-label m))))
                   (org-truss-model-members model))))
     (org-truss--list-lines model "Not placed" (plist-get checks :unplaced) 'unplaced)
     (org-truss--list-lines model "Only as grounds" (plist-get checks :grounds-only) 'grounds)
     (org-truss--list-lines model "Bare (no source, no support)"
                            (funcall argued (plist-get checks :bare)) 'bare)
     (org-truss--list-lines model "Open questions" (funcall argued (plist-get checks :questions))
                            'questions)
     (org-truss--list-lines model "Assumptions" (funcall argued (plist-get checks :assumptions))
                            'assumptions)
     (org-truss--list-lines model "Unanswered objections" (plist-get checks :unanswered) 'unanswered)
     (org-truss--list-lines model "Pattern gaps" (funcall argued gaps) 'gaps)
     (org-truss--list-lines model "Misplaced" (funcall argued (mapcar #'car misplaced))
                            'misplaced why)
     (let ((broken (plist-get checks :broken-grounds)))
       (org-truss--list-lines model "Broken grounds" (seq-uniq (mapcar #'car broken)) 'broken-grounds
                              (lambda (m)
                                (propertize (mapconcat (lambda (b) (format "[[%s]]" (org-truss--target (cdr b))))
                                                       (seq-filter (lambda (b) (eq (car b) m)) broken)
                                                       " ")
                                            'face 'org-truss-attention))))
     (list (org-truss--line ""))
     (org-truss--structure-lines model)
     (and (or (plist-get checks :section-gaps) (plist-get checks :broken)
              (plist-get checks :duplicates))
          (list (org-truss--line "")))
     (let ((gaps (plist-get checks :section-gaps)))
       (and gaps
            (cons (org-truss--check-heading "Pattern gaps")
                  (mapcar (lambda (g)
                            (let ((root (eq (car g) (org-truss-model-structure model))))
                              (org-truss--line
                               (concat "   " (if root "Structure"
                                                 (let ((roles (org-truss-section-roles (car g))))
                                                   (if roles (org-truss-role-names roles) "no role"))))
                               ;; The Structure's heading is not the document's; the
                               ;; pattern that asks is named in its place.
                               (if root
                                   (let ((asks (or (org-truss-section-logic (car g))
                                                   (org-truss-section-telling (car g)))))
                                     (propertize (if asks (org-truss-pattern-label asks)
                                                   "an assumption is in use")
                                                 'face 'org-truss-dim))
                                 (org-truss-section-label (car g)))
                               (propertize (org-truss-role-names (mapcar #'car (cdr g)))
                                           'face 'org-truss-attention)
                               (list :type 'section :pos (org-truss-section-pos (car g))
                                     :label (org-truss-section-label (car g)) :root root
                                     :key (list 'section-gaps
                                                (if root 'root (org-truss-section-label (car g))))))))
                          gaps))))
     (let ((broken (plist-get checks :broken)))
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
                          broken))))
     (let ((duplicates (plist-get checks :duplicates)))
       (and duplicates
            (list (org-truss--line (propertize " Duplicate ids" 'face 'org-truss-section
                                               'help-echo (org-truss-check-about "Duplicate ids"))
                                   (propertize (mapconcat (lambda (id) (concat "#" id)) duplicates " · ")
                                               'face 'org-truss-attention))))))))

(defun org-truss--column (lines)
  "Return the column the file's words start at on LINES.
Two past the widest of the board's own words on a line that has any."
  (+ 2 (seq-reduce (lambda (widest line)
                     (if (plist-get line :text)
                         (max widest (string-width (plist-get line :left)))
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
LINES and OTHER are the board drawn with entry text and without, one each,
so the same lines come in the same order in both; each takes the lines it
takes below it there."
  (let ((groups (org-truss--groups lines))
        (others (org-truss--groups other)))
    (if (/= (length groups) (length others))
        lines
      (cl-mapcan (lambda (group other)
                   (cdr (if (member (car group) org-truss--wrapping) other group)))
                 groups others))))

(defun org-truss-board-text (model &optional entries width)
  "Return the board for MODEL as a string, with entry text when ENTRIES.
The lines `org-truss--wrapping' holds are drawn the other way.  The file's
words start one column for every line.  WIDTH is that of the window the
board is drawn for: right of that column, the file's words and what the
reader sees share it, and entry text is broken to fit; see
`org-truss-board-heading-width' and `org-truss-board-reader-width'."
  (let* ((plain (let ((org-truss--entries nil)) (org-truss--board-lines model)))
         ;; Where the file's words start does not depend on entry text, so
         ;; the drawing without it says.
         (column (org-truss--column plain))
         (room (and width (- width 1 column)))
         (org-truss--heading-width
          (cond (org-truss-board-heading-width)
                ;; Two of the file's columns go to the gap before the
                ;; reader's, so each side gets the same room for words.
                (room (max 20 (/ (+ room 2) 2)))
                (t 40)))
         (org-truss--reader-width
          (cond (org-truss-board-reader-width)
                (room (max 20 (- room org-truss--heading-width)))
                (t 60)))
         (org-truss--text-column column)
         (whole (and (or entries org-truss--wrapping)
                     (let ((org-truss--entries t))
                       (mapcan #'org-truss--wrapped (org-truss--board-lines model)))))
         (lines (cond ((null org-truss--wrapping) (if entries whole plain))
                      (entries (org-truss--swap whole plain))
                      (t (org-truss--swap plain whole)))))
    (mapconcat (lambda (line) (org-truss--lay-out line column)) lines "")))

(defconst org-truss--board-help
  "write  \\[org-truss-board-new] new  \\[org-truss-board-edit] edit  \
\\[org-truss-board-rename] rename  \\[org-truss-board-kind] kind  \
\\[org-truss-board-ground] ground  \\[org-truss-board-quote] quote  \
\\[org-truss-board-refile] refile  \
\\[org-truss-board-delete] delete
place  \\[org-truss-board-place] place  \\[org-truss-board-take-out] take out  \
\\[org-truss-board-up] \\[org-truss-board-down] order
shape  \\[org-truss-board-new-section] section  \\[org-truss-board-say] say  \
\\[org-truss-board-unwrap] unwrap  \
\\[org-truss-board-pattern] pattern  \\[org-truss-board-roles] roles  \
\\[org-truss-board-flip] first/last
see    \\[org-truss-board-visit] visit  \\[org-truss-board-visit-other-window] other window  \
\\[org-truss-board-show] show  \\[org-truss-board-entry-text] entry text  \
\\[org-truss-board-wrap] wrap  \\[org-truss-board-fold] fold  \
\\[org-truss-board-view] view  \\[org-truss-board-export] export  \
\\[org-truss-board-redraw] redraw  \\[org-truss-board-save] save"
  "The keys written at the foot of the board, by what they work on.
Members are written; they are placed in the structure; the structure is
shaped; and the board and the document are seen.  Each key is looked up
where the board is drawn, so a key bound anew shows as it is.")

(defun org-truss--item ()
  "Return the item of the line at point."
  (get-text-property (line-beginning-position) 'org-truss-item))

(defun org-truss--revive ()
  "Visit the truss file again if its buffer was killed; non-nil if it was.
Work on the file starts from the board, so the file's own buffer can be
closed whenever it is not wanted: the board opens it again."
  (when (and org-truss--file (not (buffer-live-p org-truss--source)))
    (setq org-truss--source (find-file-noselect org-truss--file))
    t))

(defun org-truss--stale-p ()
  "Non-nil when the text of the truss file changed since the board was drawn."
  (not (eq org-truss--drawn-tick (buffer-chars-modified-tick org-truss--source))))

(defun org-truss--before-command ()
  "Draw the board again before a command, if the file changed under it.
If the file's buffer was killed it is visited again; if its text changed,
by hand or by anything else, the board draws it as it is now.  So a
command acts on the file as it is, and a key pressed once is enough."
  (condition-case err
      (when (or (org-truss--revive) (org-truss--stale-p))
        (org-truss-board-redraw))
    (error (message "org-truss: %s" (error-message-string err)))))

(defun org-truss-board-redraw (&rest _)
  "Draw the board again from its truss file, keeping point on the same line."
  (interactive)
  (org-truss--revive)
  (unless (buffer-live-p org-truss--source)
    (user-error "The truss file's buffer is gone"))
  (let ((key (plist-get (org-truss--item) :key))
        (line (line-number-at-pos))
        (inhibit-read-only t)
        (model (org-truss-read org-truss--source))
        (window (get-buffer-window (current-buffer) t)))
    (setq org-truss--drawn-width (and window (window-body-width window)))
    (erase-buffer)
    (insert (let ((org-truss--folding org-truss--folds)
                  (org-truss--wrapping org-truss--wraps))
              (org-truss-board-text model org-truss--entry-text org-truss--drawn-width))
            "\n" (propertize (substitute-command-keys org-truss--board-help t)
                             'face 'org-truss-dim)
            "\n")
    (setq org-truss--drawn-tick (buffer-chars-modified-tick org-truss--source))
    (when (and (buffer-live-p org-truss--view) (get-buffer-window org-truss--view t))
      (org-truss--fill-view org-truss--view model))
    (goto-char (point-min))
    (let ((found (and key (text-property-search-forward
                           'org-truss-item key
                           (lambda (k item) (equal k (plist-get item :key)))))))
      (if found
          (goto-char (prop-match-beginning found))
        (goto-char (point-min))
        (forward-line (1- line))))))

(defvar org-truss-board-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'org-truss-board-visit)
    (define-key map (kbd "TAB") #'org-truss-board-visit-other-window)
    (define-key map (kbd "SPC") #'org-truss-board-show)
    (define-key map (kbd "e") #'org-truss-board-edit)
    (define-key map (kbd "E") #'org-truss-board-entry-text)
    (define-key map (kbd "w") #'org-truss-board-wrap)
    (define-key map (kbd "z") #'org-truss-board-fold)
    (define-key map (kbd "c") #'org-truss-board-new)
    (define-key map (kbd "R") #'org-truss-board-rename)
    (define-key map (kbd "t") #'org-truss-board-kind)
    (define-key map (kbd "b") #'org-truss-board-ground)
    (define-key map (kbd "Q") #'org-truss-board-quote)
    (define-key map (kbd "f") #'org-truss-board-refile)
    (define-key map (kbd "D") #'org-truss-board-delete)
    (define-key map (kbd "a") #'org-truss-board-place)
    (define-key map (kbd "d") #'org-truss-board-take-out)
    (define-key map (kbd "s") #'org-truss-board-new-section)
    (define-key map (kbd "S") #'org-truss-board-say)
    (define-key map (kbd "u") #'org-truss-board-unwrap)
    (define-key map (kbd "p") #'org-truss-board-pattern)
    (define-key map (kbd "r") #'org-truss-board-roles)
    (define-key map (kbd "o") #'org-truss-board-flip)
    (define-key map (kbd "M-<up>") #'org-truss-board-up)
    (define-key map (kbd "M-<down>") #'org-truss-board-down)
    (define-key map (kbd "P") #'org-truss-board-view)
    (define-key map (kbd "x") #'org-truss-board-export)
    (define-key map (kbd "g") #'org-truss-board-redraw)
    (define-key map [remap save-buffer] #'org-truss-board-save)
    map)
  "Keys of the board.")

(defun org-truss--catch-up (window)
  "Draw the board in WINDOW again, if it is selected and its file has changed.
So an edit made in the file, or with \\[org-truss-board-edit], is on the
board when you come back to it."
  (with-current-buffer (window-buffer window)
    (when (eq window (selected-window))
      (org-truss--revive)
      (when (and (buffer-live-p org-truss--source)
                 (org-truss--stale-p))
        (org-truss-board-redraw)))))

(defun org-truss--refit (window)
  "Draw the board in WINDOW again when its columns no longer fit it.
The file's words take half the window, and entry text is broken to its
width, so a new width wants a new drawing."
  (with-current-buffer (window-buffer window)
    (when (and (or (null org-truss-board-heading-width)
                   (and (or org-truss--entry-text org-truss--wraps)
                        (null org-truss-board-reader-width)))
               (buffer-live-p org-truss--source)
               (not (eql org-truss--drawn-width (window-body-width window))))
      (org-truss-board-redraw))))

(define-derived-mode org-truss-board-mode special-mode "Truss"
  "The structure of a truss file, with what it leaves undone.
\\{org-truss-board-mode-map}"
  (setq-local revert-buffer-function #'org-truss-board-redraw)
  (setq-local truncate-lines t)
  (add-hook 'window-selection-change-functions #'org-truss--catch-up nil t)
  (add-hook 'pre-command-hook #'org-truss--before-command nil t)
  (add-hook 'window-size-change-functions #'org-truss--refit nil t))

(declare-function org-truss-init "org-truss" (directory))

(defun org-truss--ask-file ()
  "Ask for a truss file, as `find-file' asks for a file, and return it.
The answer can be the file, its directory, or anything below that: the
nearest truss file at or above it is the one.  Where there is none, offer
to start one there, making the directory if it is new."
  (let* ((path (expand-file-name
                (read-file-name "Truss file or directory: "
                                (file-name-as-directory (org-truss--default-directory))
                                nil 'confirm)))
         (dir (file-name-as-directory
               (if (or (file-directory-p path) (not (file-exists-p path)))
                   path
                 (file-name-directory path)))))
    (cond ((and (file-regular-p path)
                (equal (file-name-nondirectory path) org-truss-file-name))
           path)
          ((and (file-directory-p dir) (org-truss-locate dir)))
          ((y-or-n-p (format "No %s in %s; start one there? "
                             org-truss-file-name (abbreviate-file-name dir)))
           (make-directory dir t)
           (org-truss-init dir)
           (buffer-file-name))
          (t (user-error "No %s in %s" org-truss-file-name (abbreviate-file-name dir))))))

(defun org-truss-board (&optional ask)
  "Draw the board for the nearest truss file, from anywhere.
The current buffer's, when it is one; else the nearest at or above the
current directory.  When there is none, or with a prefix argument ASK, a
truss file is asked for as `find-file' asks for a file: the file, its
directory, or anything in it; see `org-truss--ask-file'.

The board is where a truss file is worked from.  The file's own buffer can
be closed whenever it is not wanted -- the board visits it again -- and
\\[save-buffer] on the board saves it."
  (interactive "P")
  (let* ((file (or (and (not ask) (org-truss-locate))
                   (org-truss--ask-file)))
         (source (find-file-noselect file))
         (board (get-buffer-create
                 (format "*truss %s*" (abbreviate-file-name (file-name-directory file))))))
    (with-current-buffer board
      (unless (derived-mode-p 'org-truss-board-mode)
        (org-truss-board-mode))
      (setq org-truss--source source
            org-truss--file file
            ;; The board belongs to the file's directory, as dired and magit
            ;; do, so a shell, a compile, or an agent started from it starts
            ;; there.
            default-directory (file-name-directory file))
      (org-truss-board-redraw))
    (pop-to-buffer board)))

(defun org-truss-board-save ()
  "Save the truss file, from the board."
  (interactive)
  (with-current-buffer org-truss--source
    (save-buffer))
  (org-truss-board-redraw))

;;;; Commands

(defun org-truss--fresh ()
  "Signal unless the board shows the truss file as it is now.
An edit since the last draw moves the positions the board holds.  The
board draws again before every command, so this catches only an edit made
while a command was asking something."
  (when (org-truss--stale-p)
    (org-truss-board-redraw)
    (user-error "The file changed since the board was drawn; drawn again, try once more")))

(defmacro org-truss--editing (&rest body)
  "Run BODY in the truss file, then draw the board again."
  (declare (indent 0) (debug t))
  `(progn
     (org-truss--fresh)
     (with-current-buffer org-truss--source
       (org-with-wide-buffer ,@body))
     (org-truss-board-redraw)))

(defun org-truss--want (item &rest types)
  "Return ITEM when its type is one of TYPES; otherwise say what the key needs."
  (if (and item (memq (plist-get item :type) types))
      item
    (user-error "Put point on a %s line"
                (mapconcat #'symbol-name types " or "))))

(defun org-truss--read-choice (prompt alist &optional about)
  "Read one of ALIST's names with PROMPT and return its value.
ABOUT, if given, maps a name to a few words said beside it as it is offered."
  (let* ((completion-extra-properties
          (and about (list :annotation-function
                           (lambda (name)
                             (let ((text (cdr (assoc name about))))
                               (and text (concat "  " (propertize text 'face 'completions-annotations))))))))
         (name (completing-read prompt (mapcar #'car alist) nil t)))
    (cdr (assoc name alist))))

(defun org-truss--read-roles (prompt current parent)
  "Read roles for a section with PROMPT, offering CURRENT as the default.
PARENT is the section it is under: the roles its patterns ask for come
first, those no section answers yet before the rest, then every reader's
question."
  (let* ((asked (and parent (org-truss-member-roles parent)))
         (open (and parent (mapcar #'car (org-truss-gaps parent))))
         (alist (mapcar (lambda (r) (cons (org-truss-role-name r) r))
                        (seq-uniq (append open asked (mapcar #'car org-truss-questions)))))
         (names (completing-read-multiple
                 prompt (mapcar #'car alist) nil t
                 (and current (mapconcat #'org-truss-role-name current ",")))))
    (delq nil (mapcar (lambda (n) (cdr (assoc n alist))) names))))

(defun org-truss--section-at (item &optional above)
  "Return the section the board line ITEM stands for, or with ABOVE the one
it is under; nil for the structure's own above."
  (let* ((root (org-truss-model-structure (org-truss-read org-truss--source)))
         (pos (plist-get item :pos))
         found)
    (cl-labels ((walk (section up)
                  (if (= (org-truss-section-pos section) pos)
                      (setq found (list (if above up section)))
                    (dolist (c (org-truss-section-children section))
                      (unless found (walk c section))))))
      (when root (walk root nil)))
    (car found)))

(defun org-truss--section-choices (model)
  "Return (PATH . POS) for every section of MODEL, the root first.
The root is called Structure, and each section below by the questions it
answers and then its heading, as on the board."
  (let (out)
    (cl-labels ((walk (section path)
                  (let* ((roles (org-truss-section-roles section))
                         (path (if path
                                   (concat path " › "
                                           (if roles
                                               (concat (org-truss-role-names roles) " › ")
                                             "")
                                           (org-truss-section-label section))
                                 "Structure")))
                    (push (cons (if (assoc path out)
                                    (format "%s <%d>" path (org-truss-section-pos section))
                                  path)
                                (org-truss-section-pos section))
                          out)
                    (dolist (c (org-truss-section-children section))
                      (walk c path)))))
      (let ((root (org-truss-model-structure model)))
        (when root (walk root nil))))
    (nreverse out)))

(defun org-truss--go (display &optional center)
  "Show the truss file with DISPLAY, at the heading the line at point stands for.
Its entry is shown, and the blocks in it open: a heading is gone to so its
text can be read, and the public block and the quotation are part of that
text, though `org-hide-block-startup' folds them.  The headings under it
are left as they were.  CENTER leaves a mark where point was in the file
and puts the heading mid-window."
  (let ((item (org-truss--want (org-truss--item) 'section 'member 'broken 'brief)))
    (funcall display org-truss--source)
    (widen)
    (when center (push-mark))
    (goto-char (plist-get item :pos))
    (org-fold-show-context 'link-search)
    (org-fold-show-entry)
    (org-fold-region (point) (cdr (org-truss--own-bounds (point))) nil 'block)
    (when center (recenter (/ (window-height) 2)))))

(defun org-truss-board-visit ()
  "Go to the line's heading in the truss file, in this window.
As RET does in the agenda: the file takes the board's window."
  (interactive)
  (org-truss--go #'pop-to-buffer-same-window))

(defun org-truss-board-visit-other-window ()
  "Go to the line's heading in the truss file, in another window.
As TAB does in the agenda: a window already showing the file is used, or a
new one is made, and point goes there."
  (interactive)
  (org-truss--go (lambda (buffer)
                   (pop-to-buffer buffer '((display-buffer-reuse-window
                                            display-buffer-pop-up-window)
                                           (reuse-indirect . buffer))))
                 t))

(defvar-local org-truss--show-window nil
  "The window `org-truss-board-show' last showed the truss file in.")

(defun org-truss-board-show ()
  "Show the line's heading in the truss file in another window, staying here.
As SPC does in the agenda: pressed again, it scrolls that window."
  (interactive)
  (let ((board (selected-window)))
    (if (and (eq this-command last-command) (window-live-p org-truss--show-window))
        (with-selected-window org-truss--show-window
          (ignore-errors (scroll-up)))
      (org-truss-board-visit-other-window)
      (let ((shown (selected-window)))
        (select-window board)
        (setq org-truss--show-window shown)))))

(defun org-truss--pattern-about (id)
  "Return what the board says beside the pattern ID as it is offered."
  (let ((pattern (org-truss-pattern id)))
    (cond ((eq id :none) "no logic pattern: nothing is asked of the sections below")
          ((plist-get pattern :slots) (mapconcat #'car (plist-get pattern :slots) " / "))
          (t (plist-get pattern :about)))))

(defun org-truss--pattern-choices (section &optional material)
  "Return (LABEL . ID) for the patterns for a SECTION, or else for a member.
Any cluster takes any logic pattern: why it holds or what it is made of,
and so what is right under it is asked for -- the reader's questions a
proposal answers, the parts of a 6W1H.  A section also takes a telling
pattern that gives it its sections, and its logic can be taken off, as
:none.  A member of the members takes a telling pattern for the order it
is told in; a MATERIAL member, one of the subject, is not told, only
listed."
  (append (mapcar (lambda (id) (cons (org-truss-pattern-label id) id))
                  (append (org-truss-patterns-of-kind 'logic)
                          (cond (section (org-truss-patterns-of-kind 'structure))
                                ((not material) (org-truss-patterns-of-kind 'telling)))))
          (and section (list (cons "no logic" :none)))))

(defun org-truss-board-pattern ()
  "Apply a pattern to the cluster at point: a member, a section, the structure.
A logic pattern says what is right under it is to it -- why it holds, or
what it is made of -- and so what it asks for: the reader's questions a
proposal answers are asked of the sections below, the parts of a 6W1H of
the members under it.  A telling pattern says in what order it is told; a
section's gives it its sections.  Each is offered by where it stands:
why › deduction, how › proposal, tell › PREP."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'section 'member))
         (section (eq (plist-get item :type) 'section))
         (material (and (not section)
                        (org-truss-material-p
                         (org-truss--member-at (org-truss-read org-truss--source) item))))
         (choices (org-truss--pattern-choices section material))
         (id (org-truss--read-choice
              "Pattern: " choices
              (mapcar (lambda (c) (cons (car c) (org-truss--pattern-about (cdr c)))) choices)))
         (kind (plist-get (org-truss-pattern id) :kind))
         (pos (plist-get item :pos)))
    (org-truss--editing
      (cond ((eq id :none) (org-truss-set-logic pos nil))
            ((eq kind 'structure) (org-truss-apply-structure-pattern pos id))
            ((eq kind 'telling) (org-truss-set-telling pos id))
            (t (org-truss-set-logic pos id))))))

(defun org-truss-board-new-section ()
  "Add a section under the section at point.
On a gap -- a reader's question the section's pattern asks for and no
section below answers -- the new section answers it."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'section))
         (gap (plist-get item :gap))
         (roles (if gap (list gap)
                  (org-truss--read-roles "Answers (empty for none): " nil
                                         (org-truss--section-at item))))
         (name (read-string "Label: " (and roles (org-truss-role-label (car roles))))))
    (org-truss--editing
      (org-truss-add-section (plist-get item :pos) name roles))))

(defun org-truss--field-name (key)
  "Return the board's name for the field KEY, (PART FIELD), with its part."
  (format "%s › %s" (capitalize (symbol-name (car key)))
          (string-trim (or (nth 1 (assoc key org-truss--board-fields))
                           (capitalize (symbol-name (cadr key)))))))

(defun org-truss--path-segment (model member short)
  "Return MEMBER as one step of a path, cut short when SHORT.
A step says its number, and a part its role or that it is a part."
  (let* ((label (org-truss-member-label member))
         (label (if short (truncate-string-to-width label 20 nil nil "…") label))
         (up (org-truss-parent model member)))
    (if (not (and up (org-truss-how-child-p model member)))
        label
      (pcase (org-truss-how-list up)
        ('numbered
         (let ((n (seq-position (seq-remove #'org-truss-noexport-p (org-truss-how-children up))
                                member)))
           (if n (format "step %d: %s" (1+ n) label) (format "step: %s" label))))
        ('labelled
         (let ((role (org-truss-member-role member)))
           (format "%s: %s" (if role (org-truss-role-name role) "part") label)))
        (_ (format "part: %s" label))))))

(defun org-truss--member-path (model member)
  "Return where MEMBER of MODEL is, as a path, to choose it by.
From where it is written -- Members, or the field it states -- through the
members it is nested under, their headings cut short, to its own heading,
whole.  A heading is what names a member; the path says where it is."
  (let ((top member)
        (segments (list (org-truss--path-segment model member nil))))
    (while (org-truss-parent model top)
      (setq top (org-truss-parent model top))
      (push (org-truss--path-segment model top t) segments))
    (let ((field (car (seq-find (lambda (c) (memq top (cdr c)))
                                (org-truss-model-conditions model)))))
      (string-join (cons (if field (org-truss--field-name field) "Members") segments) " › "))))

(defun org-truss--member-choices (model)
  "Return (PATH . POSITION) for every member of MODEL, the unplaced first."
  (let ((unplaced (plist-get (org-truss-checks model) :unplaced)))
    (mapcar (lambda (m) (cons (org-truss--member-path model m) (org-truss-member-pos m)))
            (append unplaced
                    (seq-remove (lambda (m) (memq m unplaced)) (org-truss-model-all model))))))

(defun org-truss--placings (model ref)
  "Return the sections of MODEL that place the member REF."
  (let ((root (org-truss-model-structure model)))
    (and root (seq-filter (lambda (s) (member ref (org-truss-section-links s)))
                          (cons root (org-truss-sections model))))))

(defun org-truss--place (pos to)
  "Place the member at POS in the section at TO, and nowhere else.
Run in the truss file.  The member is given a CUSTOM_ID to be pointed to
by, when it has none.  A member is placed in one section at most: where
it was placed, it is taken out, and the words it was told in there go with
it."
  (let* ((to (copy-marker to))
         (ref (org-truss-ensure-id pos))
         (placings (org-truss--placings (org-truss-read) ref))
         (from (mapcar #'org-truss-section-pos placings))
         (wording (seq-some (lambda (s) (org-truss-section-wording s ref)) placings)))
    (if (equal from (list (marker-position to)))
        (message "Already placed there")
      (dolist (pos (sort from #'>))
        (org-truss-remove-link pos ref))
      (org-truss-add-link to ref wording))
    (set-marker to nil)))

(defun org-truss-board-place ()
  "Place a member in a section of the structure.
On a section, ask which member to place in it, those not placed yet
first.  On a broken link, ask which member to place where it stands, in
its place.  On a member, ask which section to place it in.  A member is
placed in one section at most, so one placed already is moved.  The member
itself, in the file, does not move: the section lists it."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'section 'member 'broken))
         (model (org-truss-read org-truss--source)))
    (pcase (plist-get item :type)
      ('section
       (let ((pos (org-truss--read-choice "Place: " (org-truss--member-choices model))))
         (org-truss--editing (org-truss--place pos (plist-get item :pos)))))
      ('broken
       (let ((pos (org-truss--read-choice
                   (format "Place instead of [[%s]]: " (org-truss--target (plist-get item :link)))
                   (org-truss--member-choices model))))
         (org-truss--editing
           (let* ((section (copy-marker (plist-get item :section)))
                  (ref (org-truss-ensure-id pos)))
             (dolist (pos (sort (mapcar #'org-truss-section-pos
                                        (org-truss--placings (org-truss-read) ref))
                                #'>))
               (org-truss-remove-link pos ref))
             (org-truss-relink section (plist-get item :link) ref)
             (set-marker section nil)))))
      (_
       (let ((pos (or (and (plist-get item :label) (plist-get item :pos))
                      (user-error "Nothing to place here")))
             (to (org-truss--read-choice "Place in: " (org-truss--section-choices model))))
         (org-truss--editing (org-truss--place pos to)))))))

(defun org-truss--confirm-loss (labels)
  "Ask whether to lose the writing in the sections LABELS; non-nil means yes."
  (y-or-n-p (format "Discard the titles and notes of %s? " (string-join labels ", "))))

(defun org-truss-board-take-out ()
  "Take what is at point out of the structure, losing nothing written.
On a placed member, the section stops listing it; the member stays in the
file.  On a section, the section goes, handing what it places up to the
section above, and asking before its own title or notes are lost."
  (interactive)
  (let ((item (org-truss--want (org-truss--item) 'member 'broken 'section)))
    (cond
     ((plist-get item :link)
      (org-truss--editing
        (org-truss-remove-link (plist-get item :section) (plist-get item :link))))
     ((eq (plist-get item :type) 'section)
      (when (plist-get item :root)
        (user-error "The root of the structure stays"))
      (let ((parent (with-current-buffer org-truss--source
                      (org-with-point-at (plist-get item :pos)
                        (org-up-heading-safe)
                        (point)))))
        (org-truss--fresh)
        (let ((lost (with-current-buffer org-truss--source
                      (org-truss-dissolve (plist-get item :pos) parent))))
          (when (and lost (org-truss--confirm-loss lost))
            (with-current-buffer org-truss--source
              (org-truss-dissolve (plist-get item :pos) parent t))))
        (org-truss-board-redraw)))
     (t (user-error "This member is not placed; %s deletes it"
                    (substitute-command-keys "\\[org-truss-board-delete]"))))))

(defun org-truss-board-delete ()
  "Delete the member at point from the file, with what is nested under it.
After asking.  What placed it, or a member under it, in the structure goes
too.  A ground that names one is left, and shows as a broken link, so what
stood on it can be seen."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (model (org-truss-read org-truss--source))
         (member (org-truss--member-at model item))
         (under (1- (length (org-truss--subtree member)))))
    (when (y-or-n-p (format "Delete %s%s? " (org-truss-member-label member)
                            (if (> under 0) (format " and the %d under it" under) "")))
      (org-truss--editing
        (org-truss-delete-member (plist-get item :pos))))))

(defun org-truss-board-ground ()
  "Make another member a ground of the member at point, or no longer one.
A ground supports a member from outside what is nested under it, through
TRUSS_GROUNDS, which points to it by its CUSTOM_ID; one is given to it
when it has none.  Its grounds now are offered first, and choosing one
takes it away.  On a ground's own line, the one marked with an arrow, take
it away from the member it supports without asking."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (model (org-truss-read org-truss--source)))
    (if (plist-get item :claim)
        (let* ((claim (seq-find (lambda (m) (= (org-truss-member-pos m) (plist-get item :claim)))
                                (org-truss-model-all model)))
               (ground (plist-get item :ground)))
          (org-truss--editing
            (org-truss-set-grounds (org-truss-member-pos claim)
                                   (remove ground (org-truss-member-grounds claim))))
          (message "%s no longer grounds %s" (or (plist-get item :label) ground)
                   (org-truss-member-label claim)))
      (let* ((member (org-truss--member-at model item))
             (grounds (org-truss-member-grounds member))
             (inside (org-truss--subtree member))
             (others (seq-remove (lambda (m) (memq m inside)) (org-truss-model-all model)))
             (current (seq-filter (lambda (m) (member (org-truss-member-id m) grounds)) others))
             (choices (mapcar (lambda (m) (cons (org-truss--member-path model m) m))
                              (append current (seq-remove (lambda (m) (memq m current)) others))))
             (ground (org-truss--read-choice
                      "Ground: " choices
                      (mapcar (lambda (m) (cons (org-truss--member-path model m)
                                                "a ground now; choose to take it away"))
                              current))))
        (org-truss--editing
          (let ((at (copy-marker (plist-get item :pos))))
            (if (memq ground current)
                (org-truss-set-grounds at (remove (org-truss-member-id ground) grounds))
              (let ((ref (org-truss-ensure-id (org-truss-member-pos ground))))
                (org-truss-set-grounds at (append grounds (list ref)))))
            (set-marker at nil)))))))

(defun org-truss-board-unwrap ()
  "Take away the sections below the section at point, keeping their links."
  (interactive)
  (let ((item (org-truss--want (org-truss--item) 'section)))
    (org-truss--fresh)
    (let ((lost (with-current-buffer org-truss--source
                  (org-truss-unwrap (plist-get item :pos)))))
      (when (and lost (org-truss--confirm-loss lost))
        (with-current-buffer org-truss--source
          (org-truss-unwrap (plist-get item :pos) t))))
    (org-truss-board-redraw)))

(defun org-truss-board-roles ()
  "Set what the line at point answers.
For a section, the reader's questions, or the roles the pattern of the
section above names, those it still lacks first; for a member, its role
under the member above, when that one's pattern names roles."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'section 'member))
         (pos (plist-get item :pos)))
    (if (eq (plist-get item :type) 'section)
        (let ((roles (org-truss--read-roles
                      "Answers: "
                      (with-current-buffer org-truss--source
                        (mapcar #'intern (split-string (or (org-entry-get pos "TRUSS_ROLE") ""))))
                      (org-truss--section-at item t))))
          (org-truss--editing (org-truss-set-roles pos roles)))
      (let* ((model (org-truss-read org-truss--source))
             (member (seq-find (lambda (m) (= (org-truss-member-pos m) pos))
                               (org-truss-model-all model)))
             (parent (and member (org-truss-parent model member)))
             (roles (and parent (org-truss-member-roles parent))))
        (unless roles
          (user-error "A member takes a role only under one whose pattern names roles"))
        (let ((role (org-truss--read-choice
                     "Role: " (append (mapcar (lambda (r) (cons (org-truss-role-name r) r))
                                              roles)
                                      (list (cons "(none)" nil))))))
          (org-truss--editing (org-truss-set-roles pos (and role (list role)))))))))

(defun org-truss-board-flip ()
  "Tell the member at point before what is under it, or after.
A shortcut for the two telling patterns most often wanted; PREP, and the
rest, are on \\[org-truss-board-pattern]."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (pos (plist-get item :pos))
         (member (seq-find (lambda (m) (= (org-truss-member-pos m) pos))
                           (org-truss-model-all (org-truss-read org-truss--source)))))
    (org-truss--editing
      (org-truss-set-telling pos (if (eq (org-truss-conclusion-position member) 'last)
                                     'first 'last)))))

(defun org-truss-board-rename ()
  "Rewrite the heading of the section or member at point.
Links and grounds point to a member by its CUSTOM_ID, so they go on
finding it."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'section 'member))
         (new (string-trim (read-string "New heading: " (plist-get item :label)))))
    (when (string-empty-p new)
      (user-error "A heading cannot be empty"))
    (org-truss--editing
      (if (eq (plist-get item :type) 'section)
          (org-with-point-at (plist-get item :pos) (org-edit-headline new))
        (org-truss-rename (plist-get item :pos) new)))))

(defun org-truss-board-say ()
  "Write what the reader is told at point, beside what the file asserts.
On a member a section lists, the words the section tells it in, in place
of its heading.  The heading goes on saying what is asserted, so the
checks read it as before; the section says it as this reader needs.  Blank
words, or the heading's own, tell it in its heading again.

On a section, its lead: the text of its public block, read under its title
before the members it lists.  On the Structure line, the document's
opening.  On a member told with the one above it -- a step, a part, a
reason -- its public block, which the reader sees in place of its heading.
These open beside the board as an entry does; a block left empty is taken
away when it is finished."
  (interactive)
  (let ((item (org-truss--want (org-truss--item) 'section 'member)))
    (if (plist-get item :link)
        (let* ((section (plist-get item :section))
               (ref (plist-get item :link))
               (label (plist-get item :label))
               (old (with-current-buffer org-truss--source
                      (org-truss-link-wording section ref)))
               (new (string-trim (read-string "Say here: " (or old label)))))
          (org-truss--editing
            (org-truss-set-wording section ref (unless (equal new label) new))))
      (org-truss--fresh)
      (let* ((pos (plist-get item :pos))
             (session (with-current-buffer org-truss--source
                        (list :original (buffer-substring pos (cdr (org-truss--own-bounds pos)))
                              :hash (buffer-hash)
                              :modified (buffer-modified-p))))
             (at (with-current-buffer org-truss--source
                   (org-with-wide-buffer (copy-marker (org-truss-public-body pos))))))
        (org-truss-board-redraw)
        (org-truss--edit pos at session)
        (set-marker at nil)))))

(defun org-truss--fold-line (key)
  "Return where the line that folds as KEY starts on the board, or nil."
  (save-excursion
    (goto-char (point-min))
    (let ((found (text-property-search-forward
                  'org-truss-item key
                  (lambda (key item) (equal key (plist-get item :fold))))))
      (and found (prop-match-beginning found)))))

(defun org-truss-board-fold ()
  "Fold what is under the line at point, or unfold it.
On a field of the brief or the subject, the members written under it; on a
member, what is nested under it.  On a line with nothing under it, what it
is under: anywhere among a field's members, that field.  A folded line says
how many it hides.  A field holding more than `org-truss-board-fold-limit'
members starts folded."
  (interactive)
  (let* ((item (org-truss--item))
         (at (if (plist-get item :fold)
                 (line-beginning-position)
               (let ((key (butlast (plist-get item :key))) at)
                 (while (and key (not (setq at (org-truss--fold-line key))))
                   (setq key (butlast key)))
                 (or at (user-error "Nothing to fold here")))))
         (line (get-text-property at 'org-truss-item))
         (key (plist-get line :fold)))
    (setf (alist-get key org-truss--folds nil nil #'equal)
          (if (plist-get line :folded) 'open 'closed))
    (org-truss-board-redraw)
    (goto-char (or (org-truss--fold-line key) (point)))))

(defun org-truss-board-entry-text ()
  "Show the text under each heading on the board, or stop showing it.
As E does in the agenda.  What stays in the file goes under the heading, in
the file's column; the rest of what the reader sees goes on the right, so
the document can be read down the right of the board.  Every line is drawn
the same way again, whatever \\[org-truss-board-wrap] did to it."
  (interactive)
  (setq org-truss--entry-text (not org-truss--entry-text)
        org-truss--wraps nil)
  (org-truss-board-redraw)
  (message "Entry text %s" (if org-truss--entry-text "shown" "hidden")))

(defun org-truss-board-wrap ()
  "Draw the line at point whole, or on one line again; the rest stay as they are.
Whole is as \\[org-truss-board-entry-text] draws every line: its words
broken to fit, and under a heading what is written under it.  So the board
can be scanned a line each and a line read through.  While entry text is
shown, this puts the line back on one line instead."
  (interactive)
  (let ((key (org-truss--owner (plist-get (org-truss--item) :key)))
        (start (point)))
    (unless key (user-error "Nothing to wrap here"))
    ;; To the line's own first, where the board puts point back.
    (while (and (not (equal (plist-get (org-truss--item) :key) key))
                (zerop (forward-line -1))))
    (unless (equal (plist-get (org-truss--item) :key) key)
      (goto-char start))
    (setq org-truss--wraps (if (member key org-truss--wraps)
                               (delete key org-truss--wraps)
                             (cons key org-truss--wraps)))
    (org-truss-board-redraw)))

(defun org-truss-board-edit ()
  "Edit the heading of the line at point on its own, in another window.
The heading and what is written under it, up to the next heading, are shown
alone in a buffer sharing the truss file's text, so the rest of the file
stays out of the way.  As in a capture buffer, \\<org-truss-edit-mode-map>\
\\[org-truss-edit-finish] saves the file and closes
it, and \\[org-truss-edit-abort] puts back what was there and closes it.
Back on the board, it draws again."
  (interactive)
  (org-truss--edit (plist-get (org-truss--want (org-truss--item) 'section 'member 'broken 'brief)
                              :pos)))

(defvar-local org-truss--edit-session nil
  "How to take back what was done in this edit buffer, and where to go after.
A plist: :original, the text the buffer held when it opened; :hash and
:modified, the truss file's buffer then; :undo, a function that takes back
the rest of what writing it did; :board, the board it was opened from.")

(defvar org-truss-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'org-truss-edit-finish)
    (define-key map (kbd "C-c C-k") #'org-truss-edit-abort)
    map)
  "Keys of a buffer editing one entry of a truss file.")

(define-minor-mode org-truss-edit-mode
  "One entry of a truss file, edited on its own.
\\{org-truss-edit-mode-map}"
  :lighter " Truss-Edit"
  (when org-truss-edit-mode
    (setq-local header-line-format
                (substitute-command-keys
                 "\\<org-truss-edit-mode-map>Truss entry.  \
Finish `\\[org-truss-edit-finish]', abort `\\[org-truss-edit-abort]'."))))

(defun org-truss--edit (pos &optional body session)
  "Show the heading at POS on its own in another window, to be edited.
With BODY, point goes below the heading and its drawers, where its text is
written, or to BODY itself when it is a position; otherwise to the heading.
SESSION, when the heading has just been written, says how to take it back,
as `org-truss--edit-session' does; else aborting puts back what the buffer
holds now."
  (let ((old (get-buffer "*truss edit*"))
        (board (current-buffer))
        (source org-truss--source))
    (when old (kill-buffer old))
    (let ((buffer (make-indirect-buffer source "*truss edit*" t)))
      (with-current-buffer buffer
        (widen)
        (narrow-to-region pos (cdr (org-truss--own-bounds pos)))
        (org-fold-show-all)
        (goto-char (point-max))
        (cond ((not body) (goto-char pos))
              ((number-or-marker-p body) (goto-char body))
              (t (skip-chars-backward " \t\n")
                 (forward-line 1)))
        (org-truss-edit-mode 1)
        (setq org-truss--edit-session
              (append (list :board board)
                      (or session
                          (list :original (buffer-string)
                                :hash (with-current-buffer source (buffer-hash))
                                :modified (buffer-modified-p source))))))
      (pop-to-buffer buffer '((display-buffer-reuse-window display-buffer-pop-up-window))))))

(defun org-truss--edit-close (board)
  "Close this edit buffer and its window, and go back to BOARD if it is shown."
  (let ((window (get-buffer-window (current-buffer))))
    (if window
        (quit-window t window)
      (kill-buffer (current-buffer))))
  (let ((window (and (buffer-live-p board) (get-buffer-window board))))
    (when window
      (select-window window))))

(defun org-truss-edit-finish ()
  "Save the truss file and close this entry, going back to the board.
A public block left empty is taken away first."
  (interactive)
  (let ((board (plist-get org-truss--edit-session :board)))
    (org-truss-drop-empty-public (point-min) (point-max))
    (with-current-buffer (buffer-base-buffer)
      (save-buffer))
    (org-truss--edit-close board)))

(defun org-truss-edit-abort ()
  "Put back what this entry held when it was opened, and close it.
An entry written just now is taken away, with the link that placed it.
When the file's buffer then holds what it held before, it is unmodified
again if it was before."
  (interactive)
  (let* ((session org-truss--edit-session)
         (base (buffer-base-buffer)))
    (let ((inhibit-read-only t))
      (delete-region (point-min) (point-max))
      (insert (plist-get session :original)))
    (with-current-buffer base
      (let ((undo (plist-get session :undo)))
        (when undo (funcall undo)))
      (when (and (not (plist-get session :modified))
                 (equal (buffer-hash) (plist-get session :hash)))
        (set-buffer-modified-p nil)))
    (org-truss--edit-close (plist-get session :board))))

(defun org-truss--goto-label (label)
  "Put point on the first line of the board for the member LABEL, if any."
  (let ((found (save-excursion
                 (goto-char (point-min))
                 (text-property-search-forward
                  'org-truss-item label
                  (lambda (label item) (and (eq (plist-get item :type) 'member)
                                            (equal label (plist-get item :label))))))))
    (when found
      (goto-char (prop-match-beginning found)))))

(defun org-truss--member-at (model item)
  "Return the member of MODEL the board line ITEM stands for."
  (let ((pos (plist-get item :pos)))
    (or (seq-find (lambda (m) (= (org-truss-member-pos m) pos)) (org-truss-model-all model))
        (user-error "No member here"))))

(defun org-truss--read-role (parent)
  "Read a role for a new member under PARENT, those not filled yet first."
  (let* ((roles (org-truss-member-roles parent))
         (open (mapcar #'car (org-truss-gaps parent))))
    (org-truss--read-choice
     "Role: " (append (mapcar (lambda (r) (cons (org-truss-role-name r) r))
                              (append open (seq-remove (lambda (r) (memq r open)) roles)))
                      (list (cons "(none)" nil))))))

(defun org-truss-board-new (&optional under)
  "Write a new member, and open it beside the board to be written.
Where it goes follows the line at point:

- on a step or a part, just after it, as the next one -- asking which role
  it fills, when the parts are labelled; in the subject, on a fact of a
  cluster, the next fact of that cluster;
- on any other member, under it, as what its logic pattern says: support
  for it, or, when it says how to do something, its last step or part; on
  a gap, in the role the gap wants.  A member with nothing under it yet
  starts a cluster, and is given the logic pattern that says so in the
  file: how › parts in the subject, why › reasons in the members;
- on a field of the brief or the subject, under the field;
- on a section, at the top of the members, listed in the section;
- anywhere else at the top of the members, where order means nothing:
  nothing about its place has to be decided to write it, and the board
  lists it as not placed until something uses it.

With a prefix argument UNDER, a new member on a member goes under it even
when that one is a step or a part: support for one step, say.  The entry
opens as `org-truss-board-edit' opens one, and aborting it takes the new
member away."
  (interactive "P")
  (when (eq (plist-get (org-truss--item) :part) 'subject)
    (user-error "Put point on a field of the subject to write a member under it"))
  (when (and (eq (plist-get (org-truss--item) :type) 'section) (plist-get (org-truss--item) :gap))
    (user-error (substitute-command-keys
                 "A section answers this; \\[org-truss-board-new-section] adds one")))
  (let* ((item (org-truss--item))
         (model (org-truss-read org-truss--source))
         (members (with-current-buffer org-truss--source (org-truss--part-pos "members")))
         (member (and (eq (plist-get item :type) 'member) (org-truss--member-at model item)))
         (up (and member (org-truss-parent model member)))
         (next (and member (not under) (not (plist-get item :gap))
                    (not (org-truss-how-p member))
                    (org-truss-how-child-p model member)))
         (parent (cond (member (plist-get item :pos))
                       ((plist-get item :field) (plist-get item :pos))
                       (members)
                       (t (user-error "No members part to write it in"))))
         (section (and (eq (plist-get item :type) 'section) (plist-get item :pos)))
         (label (string-trim (read-string (if next "Next: " "New member: "))))
         (role (if (and next (eq (org-truss-how-list up) 'labelled))
                   (org-truss--read-role up)
                 (plist-get item :gap)))
         ;; Listed in a section, it is pointed to from the start.
         (id (and section (with-current-buffer org-truss--source (org-truss--next-id))))
         (props (append (and id (list (cons "CUSTOM_ID" id)))
                        (and role (list (cons "TRUSS_ROLE" (symbol-name role))))))
         (session (with-current-buffer org-truss--source
                    (list :original "" :hash (buffer-hash) :modified (buffer-modified-p))))
         at)
    (when (string-empty-p label)
      (user-error "A member needs a heading"))
    (when (org-truss-member-by-label model label)
      (user-error "A member is already labelled %s" label))
    ;; What it is written under is unfolded, so the board can go to it.
    (let ((fold (cond ((plist-get item :field) (list 'field (plist-get item :field)))
                      ((and member (not next))
                       (if (plist-get item :gap)
                           (butlast (plist-get item :key) 2)
                         (plist-get item :key))))))
      (when fold
        (setf (alist-get fold org-truss--folds nil nil #'equal) 'open)))
    (org-truss--editing
      (let ((section (and section (copy-marker section)))
            (head (and member (not next) (null (org-truss-member-children member))
                       (org-truss-start-cluster parent (org-truss-member-home member))
                       (copy-marker parent))))
        (setq at (if next
                     (org-truss-add-member-after parent label props)
                   (org-truss-add-member parent label props)))
        (when section
          (org-truss-add-link section id))
        (when (or section head)
          (setq session (plist-put session :undo
                                   (lambda ()
                                     (when section
                                       (org-truss-remove-link section id)
                                       (set-marker section nil))
                                     (when head
                                       (org-truss-set-logic head nil)
                                       (set-marker head nil))))))))
    (org-truss--goto-label label)
    (org-truss--edit (marker-position at) t session)
    (set-marker at nil)))

(defconst org-truss--kinds
  '(("fact" . fact) ("assumption" . assumption) ("question" . question) ("claim" . claim))
  "The kinds of member `org-truss-board-kind' writes, by the board's word.")

(defun org-truss-board-kind ()
  "Say what the member at point is, and write what makes it so.
A fact asks where it comes from, and is given it as its TRUSS_SOURCE; an
assumption asks whom to confirm it with; a question or a claim asks
nothing.  The board reads a member's kind from a property or a tag, which
is hard to think of while writing the statement; this writes them."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (model (org-truss-read org-truss--source))
         (member (org-truss--member-at model item))
         (current (car (rassq (org-truss-kind model member) org-truss--kinds)))
         (kind (cdr (assoc (completing-read "Kind: " org-truss--kinds nil t nil nil current)
                           org-truss--kinds)))
         (value (pcase kind
                  ('nil (user-error "No kind given"))
                  ('fact
                   (let ((source (string-trim (read-string "Source: "
                                                           (org-truss-member-source member)))))
                     (if (string-empty-p source)
                         (user-error "A fact is a statement with a source")
                       source)))
                  ('assumption
                   (let ((who (string-trim (read-string "Confirm with (empty for nobody): "
                                                        (org-truss-member-confirm member)))))
                     (and (not (string-empty-p who)) who))))))
    (org-truss--editing
      (org-truss-set-kind (plist-get item :pos) kind value))))

(defun org-truss-board-quote ()
  "Put the text copied last under the member at point, as its quotation.
For a fact, the words of its source, kept with it in a #+begin_quote
block that stays in the file as notes do.  Copy the passage -- here or in
a browser -- then press this on the member.  It replaces a quotation
already there, after asking."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (pos (plist-get item :pos))
         (label (org-truss-member-label (org-truss--member-at (org-truss-read org-truss--source) item)))
         (text (string-trim (or (ignore-errors (current-kill 0)) "")))
         (old (with-current-buffer org-truss--source (org-truss--quote-bounds pos)))
         (preview (truncate-string-to-width (replace-regexp-in-string "[ \t\n]+" " " text)
                                            40 nil nil "…")))
    (when (string-empty-p text)
      (user-error "Nothing has been copied"))
    (when (y-or-n-p (if old
                        (format "Replace the quotation under %s with “%s”? " label preview)
                      (format "Quote “%s” under %s? " preview label)))
      (org-truss--editing
        (org-truss-set-quote pos text)))))

(defun org-truss--file-choices (model member)
  "Return (NAME . POS) for every place in MODEL MEMBER can be moved under.
The top of the members, the fields of the brief and the subject, and every
member not nested under MEMBER, in the order of the file: a field comes
just before what is written under it.  A field is named as on the board,
with its part; a member by its path, `org-truss--member-path'."
  (let* ((members (with-current-buffer (org-truss-model-buffer model)
                    (org-with-wide-buffer (org-truss--part-pos "members"))))
         (inside (org-truss--subtree member))
         (places (append
                  (and members (list (cons members "Members")))
                  (mapcar (lambda (place) (cons (cdr place) (org-truss--field-name (car place))))
                          (seq-filter (lambda (place) (cdr (car place)))
                                      (org-truss-model-places model)))
                  (mapcar (lambda (m) (cons (org-truss-member-pos m) (org-truss--member-path model m)))
                          (seq-remove (lambda (m) (memq m inside)) (org-truss-model-all model)))))
         out)
    (dolist (place (sort places (lambda (a b) (< (car a) (car b)))))
      (let ((name (cdr place)))
        (push (cons (if (assoc name out) (format "%s <%d>" name (car place)) name) (car place))
              out)))
    (nreverse out)))

(defun org-truss-board-refile ()
  "Move the member at point, with what is nested under it, somewhere else.
To the top of the members, under a field of the brief or the subject, or
under another member, as what its logic pattern says -- support, a step,
a part.  A member with nothing under it yet starts a cluster, and is given
the logic pattern that says so, as \\[org-truss-board-new] gives it.  Links
and grounds name a member by its label, so the structure shows it wherever
it goes."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (model (org-truss-read org-truss--source))
         (member (org-truss--member-at model item))
         (to (org-truss--read-choice "Move under: " (org-truss--file-choices model member)))
         (head (seq-find (lambda (m) (and (= (org-truss-member-pos m) to)
                                          (null (org-truss-member-children m))))
                         (org-truss-model-all model))))
    (org-truss--editing
      (let ((to (copy-marker to)))
        (set-marker (org-truss-file-member (plist-get item :pos) to) nil)
        (when head
          (org-truss-start-cluster to (org-truss-member-home head)))
        (set-marker to nil)))
    (org-truss--goto-label (org-truss-member-label member))))

(defun org-truss--shift (delta)
  "Move the line at point DELTA places among its siblings."
  (let ((item (org-truss--want (org-truss--item) 'section 'member 'broken)))
    (cond
     ((plist-get item :link)
      (org-truss--editing
        (unless (org-truss-shift-link (plist-get item :section) (plist-get item :link) delta)
          (user-error "Nothing to move past"))))
     ((and (eq (plist-get item :type) 'section) (not (plist-get item :root)))
      (org-truss--editing
        (goto-char (plist-get item :pos))
        (condition-case nil
            (if (< delta 0) (org-move-subtree-up) (org-move-subtree-down))
          (error (user-error "Nothing to move past")))))
     (t (user-error "Only sections and the members they list are ordered here")))))

(defun org-truss-board-up ()
  "Move the section or listed member at point up."
  (interactive)
  (org-truss--shift -1))

(defun org-truss-board-down ()
  "Move the section or listed member at point down."
  (interactive)
  (org-truss--shift 1))

(defun org-truss--fill-view (buffer model)
  "Put the document MODEL describes into BUFFER, keeping its point."
  (with-current-buffer buffer
    (let ((inhibit-read-only t)
          (at (point)))
      (erase-buffer)
      (insert (org-truss-render model))
      (unless (derived-mode-p 'org-mode)
        (org-mode)
        (view-mode 1))
      (org-fold-show-all)
      (goto-char (min at (point-max))))))

(defun org-truss-board-view ()
  "Show the document in another window, as \[org-truss-board-export] would write it.
Nothing is written.  While it is shown, the board keeps it current."
  (interactive)
  (unless (buffer-live-p org-truss--view)
    (let ((directory default-directory))
      (setq org-truss--view
            (get-buffer-create
             (format "*truss document %s*" (abbreviate-file-name directory))))
      (with-current-buffer org-truss--view
        (setq default-directory directory))))
  (org-truss--fill-view org-truss--view (org-truss-read org-truss--source))
  (display-buffer org-truss--view '((display-buffer-reuse-window display-buffer-pop-up-window))))

(defun org-truss-board-export ()
  "Write the document."
  (interactive)
  (let ((written (org-truss-export-buffer org-truss--source)))
    (message "org-truss: wrote %s" (mapconcat #'abbreviate-file-name written ", "))))

(provide 'org-truss-board)

;;; org-truss-board.el ends here

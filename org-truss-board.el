;;; org-truss-board.el --- The board: a truss file drawn as its trusses  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 yoshzucker

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; The board draws the four divisions, each member with its trusses, and
;; Structure with the members it includes, and under each what is left
;; undone.  It is read-only: its commands change the truss file and draw
;; the board again.  Writing happens in the file; RET goes there.  How it
;; is drawn is in org-truss-draw.el; here are its mode, its buffer and its
;; commands.
;;
;; The board's own words are English whatever `org-truss-language' says, so
;; words in another language are plainly the file's.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-edit)
(require 'org-truss-guide)
(require 'org-truss-export)
(require 'org-truss-draw)
(require 'org-dock)

(defvar-local org-truss--folds nil
  "How the lines of this board set by hand are shown, as (KEY . STATE).
STATE is `folded', one line hiding what is under it; `open', one line
cut short with what is under it shown; or `whole', its words broken to
fit and its text under it, with what is under it shown.  A line with
nothing under it is folded or open alike.  A line not here is open,
or folded as `org-truss-board-fold-limit' says.")

(defvar-local org-truss--drawn-width nil
  "Width of the window the board was drawn for.")

(defvar-local org-truss--source nil
  "The truss file buffer this board draws.")

(defvar-local org-truss--file nil
  "The truss file this board draws, to visit again if its buffer is killed.")

(defvar-local org-truss--board-alone nil
  "On the board of one heading of a file that is no truss file, its marker.
Given to the file's buffer as `org-truss--alone' before the board reads
it, so that boards of two headings of one file each read their own.")

(defun org-truss--give-alone ()
  "Tell the file's buffer which heading this board reads alone, if it reads one."
  (when (and org-truss--board-alone (buffer-live-p org-truss--source))
    (let ((alone org-truss--board-alone))
      (with-current-buffer org-truss--source
        (setq org-truss--alone alone)))))

(defvar-local org-truss--drawn-tick nil
  "The source buffer's text tick when the board was drawn.
`buffer-chars-modified-tick', which counts changes to the text only.  A
change to text properties alone -- fontification, which runs whenever the
file is shown -- moves no position the board holds, and must not make the
board think the file was edited.")

(defvar org-truss--one-reading nil
  "While one command draws the board more than once, the file as read for it.
\(MODEL . CHECKS), each nil until the first drawing reads it; nil outside
such a command, when each drawing reads the file.  Folding and opening
lines change no text of the file, so TAB, which may draw the board
several times to find what a line brings, reads and checks it once.")

(defmacro org-truss--reading-once (&rest body)
  "Run BODY reading the truss file, and its sources, once however often it draws.
See `org-truss--one-reading'.  Only for a command that changes no text of
the file between its drawings."
  (declare (indent 0))
  `(let ((org-truss--one-reading (list nil))
         (org-truss--sources-read (make-hash-table :test #'equal)))
     ,@body))

(defvar-local org-truss--view nil
  "The buffer showing this board's output document, if one has been opened.")

(defvar-local org-truss--board-order 'written
  "Where this board opens a member Structure includes: `written' or `included'.
See `org-truss--order'.")

(defcustom org-truss-board-highlight t
  "Non-nil to light the line at point on the board, and the lines like it.
The line at point with `hl-line-mode'; the other lines naming the member
on it -- where it is written, where it is linked to, wherever else it
shows -- in the face `org-truss-same'."
  :type 'boolean
  :group 'org-truss)

(defface org-truss-same '((t :inherit hl-line))
  "Face for the lines naming the member on the line at point."
  :group 'org-truss)

(defvar-local org-truss--same-overlays nil
  "The overlays lighting the lines naming the member at point.")

(defvar-local org-truss--same-item nil
  "The item of the line the lines lit were lit for.")

;;;; The board's buffer

(define-prefix-command 'org-truss-board-moor-map)
(put 'org-truss-board-moor-map 'variable-documentation
     "Keys taking a source for the member at point, as org-moor takes one.
Filled by org-truss-moor.el; empty without org-moor.")

(defconst org-truss--board-commands
  '((write org-truss-board-new org-truss-board-edit
           org-truss-board-moor-map)
    (shape org-truss-board-pattern org-truss-board-roles)
    (see org-truss-board-visit org-truss-board-visit-other-window org-truss-board-show
         org-truss-board-cycle org-truss-board-cycle-all org-truss-board-fold
         org-truss-board-same
         org-truss-board-order org-truss-board-guide org-truss-board-view
         org-truss-board-export org-truss-board-redraw org-truss-board-save))
  "The board's commands, by what they work on, as its foot lists them.
Members are written; trusses are shaped; and the board and the output
document are seen.")

(defun org-truss--board-help ()
  "Return the keys written at the foot of the board, by what they work on.
Each command with a key where the board is drawn, so a key bound anew
shows as it is, named by its name after org-truss-board-; one with none is
left out, to be called by name."
  (string-join
   (delq nil (mapcar
              (lambda (group)
                (let ((keys (delq nil (mapcar
                                       (lambda (command)
                                         (let ((key (where-is-internal command nil t)))
                                           (and key (format "%s %s" (key-description key)
                                                            (if (eq command 'org-truss-board-moor-map)
                                                                "source"
                                                              (string-remove-prefix
                                                               "org-truss-board-" (symbol-name command)))))))
                                       (cdr group)))))
                  (and keys (format "%-7s %s" (car group) (string-join keys "  ")))))
              org-truss--board-commands))
   "\n"))

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
  (org-truss--give-alone)
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
  (org-truss--give-alone)
  (let ((key (plist-get (org-truss--item) :key))
        (line (line-number-at-pos))
        (inhibit-read-only t)
        (model (or (car org-truss--one-reading) (org-truss-read org-truss--source)))
        (window (get-buffer-window (current-buffer) t)))
    (when org-truss--one-reading
      (setcar org-truss--one-reading model))
    (setq org-truss--drawn-width (and window (window-body-width window)))
    (erase-buffer)
    (insert (let ((org-truss--folding org-truss--folds)
                  (org-truss--order org-truss--board-order)
                  (org-truss--checks (and org-truss--one-reading
                                          (or (cdr org-truss--one-reading)
                                              (setcdr org-truss--one-reading (org-truss-checks model)))))
                  (org-truss--images (display-images-p (and window (window-frame window)))))
              (org-truss-board-text model nil org-truss--drawn-width))
            "\n" (propertize (org-truss--board-help) 'face 'org-truss-dim)
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
        (forward-line (1- line))))
    ;; The lines lit went with the text; light them again.
    (setq org-truss--same-overlays nil
          org-truss--same-item nil)
    (when org-truss-board-highlight
      (org-truss--light-same))))

(defvar org-truss-board-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'org-truss-board-visit)
    (define-key map (kbd "o") #'org-truss-board-order)
    (define-key map (kbd "TAB") #'org-truss-board-cycle)
    (define-key map (kbd "<backtab>") #'org-truss-board-cycle-all)
    (define-key map (kbd "m") 'org-truss-board-moor-map)
    (define-key map (kbd "x") #'org-truss-board-export)
    (define-key map (kbd "?") #'org-truss-board-guide)
    (define-key map (kbd "g") #'org-truss-board-redraw)
    (define-key map [remap save-buffer] #'org-truss-board-save)
    map)
  "Keys of the board.
Few, to be laid out again: what moves through the board and reads it, a
source taken, the output document written out, what a line is for.
Every other command of the board is called by name, M-x
org-truss-board-..., or bound where you want it.")

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
The file's words take the window to its edge, cut short or broken to its
width, so a new width wants a new drawing."
  (with-current-buffer (window-buffer window)
    (when (and (null org-truss-board-middle-width)
               (buffer-live-p org-truss--source)
               (not (eql org-truss--drawn-width (window-body-width window))))
      (org-truss-board-redraw))))

(define-derived-mode org-truss-board-mode special-mode "Truss"
  "The trusses of a truss file, with what it leaves undone.
\\{org-truss-board-mode-map}"
  (setq-local revert-buffer-function #'org-truss-board-redraw)
  (setq-local truncate-lines t)
  (add-hook 'window-selection-change-functions #'org-truss--catch-up nil t)
  (add-hook 'pre-command-hook #'org-truss--before-command nil t)
  (add-hook 'window-size-change-functions #'org-truss--refit nil t)
  (when org-truss-board-highlight
    (hl-line-mode 1)
    (add-hook 'post-command-hook #'org-truss--light-same nil t)))

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
\\[save-buffer] on the board saves it.

In an Org file that is no truss file, the board is of one heading alone:
the nearest at or above point with a pattern, else, when no truss file is
near, the heading at point.  It is drawn as a member of Message is -- its
patterns, its supporting members in their roles, and what they lack --
with no Brief, Subject or Structure, and its commands work on it there:
`p' gives it a pattern, and a member for each role."
  (interactive "P")
  (if-let* ((alone (and (not ask) (org-truss--alone-here))))
      (org-truss--board-of-heading alone)
    (org-truss--board-of-file ask)))

(defun org-truss--patterned-p ()
  "Non-nil when the heading at point has a pattern of any kind."
  (seq-some (lambda (property) (org-entry-get nil property))
            (mapcar #'cdr org-truss-pattern-properties)))

(defun org-truss--alone-here ()
  "Return a marker at the heading to draw a board of alone, or nil.
In an Org file that is no truss file: the nearest heading at or above
point with a pattern; else the heading at point, when no truss file is
near to draw instead."
  (when (and (derived-mode-p 'org-mode) buffer-file-name (not (org-truss-file-p))
             (not (org-before-first-heading-p)))
    (save-excursion
      (org-back-to-heading t)
      (let ((here (point))
            found)
        (while (and (not found)
                    (progn (when (org-truss--patterned-p) (setq found (point)))
                           (and (not found) (org-up-heading-safe)))))
        (cond (found (copy-marker found))
              ((not (org-truss-locate)) (copy-marker here)))))))

(defun org-truss--board-of-heading (alone)
  "Draw the board of the heading at ALONE, its file being no truss file.
Its patterns, its supporting members, and what they ask for and it lacks,
as a member of Message is drawn; every command of the board works on it."
  (let* ((source (marker-buffer alone))
         (file (buffer-file-name source))
         (board (get-buffer-create
                 (format "*truss %s › %s*" (file-name-nondirectory file)
                         (org-with-point-at alone (org-get-heading t t t t))))))
    (with-current-buffer board
      (unless (derived-mode-p 'org-truss-board-mode)
        (org-truss-board-mode))
      (setq org-truss--source source
            org-truss--file file
            org-truss--board-alone alone
            default-directory (file-name-directory file))
      (org-truss-board-redraw))
    (pop-to-buffer board)))

(defun org-truss--board-of-file (ask)
  "Draw the board of the nearest truss file, or of one asked for with ASK."
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

(defconst org-truss--item-commands
  '(org-truss-board-visit org-truss-board-visit-other-window org-truss-board-show
    org-truss-board-edit org-truss-board-same
    org-truss-board-pattern org-truss-board-roles
    org-truss-board-take-url org-truss-board-take-file org-truss-board-take-clipboard
    org-truss-board-keep-copy org-truss-board-link-source)
  "The board's commands that take a member written as an item of a list.")

(defun org-truss--want (item &rest types)
  "Return ITEM when its type is one of TYPES; otherwise say what the key needs.
A member written as an item of a list is no heading, and only the
commands of `org-truss--item-commands' take it, or a link one holds; see
`org-truss--item-holder'."
  (unless (and item (memq (plist-get item :type) types))
    (user-error "Put point on a %s line"
                (mapconcat #'symbol-name types " or ")))
  (when (and (not (memq this-command org-truss--item-commands))
             (seq-some #'org-truss--item-holder
                       (delq nil (list (plist-get item :pos) (plist-get item :holder)))))
    (user-error "An item of a list in its heading's text: %s writes it there"
                (substitute-command-keys "\\[org-truss-board-edit]")))
  item)

(defun org-truss--in-structure-item-p (item)
  "Non-nil when ITEM is the line of Structure or of one of its members."
  (or (plist-get item :structure)
      (and (eq (plist-get item :type) 'division) (eq (plist-get item :division) 'structure))))

(defun org-truss--item-holder (pos)
  "Return where the heading is whose text holds the item at POS, or nil.
Nil when POS, in the truss file, is a heading's, or the title's."
  (with-current-buffer org-truss--source
    (org-with-wide-buffer
     (goto-char pos)
     (and (org-at-item-p)
          (not (org-before-first-heading-p))
          (progn (org-back-to-heading t) (point))))))

(defun org-truss--read-choice (prompt alist &optional about default)
  "Read one of ALIST's names with PROMPT and return its value.
ABOUT, if given, maps a name to a few words said beside it as it is offered.
DEFAULT, if given, is the name taken when nothing is typed."
  (let* ((completion-extra-properties
          (and about (list :annotation-function
                           (lambda (name)
                             (let ((text (cdr (assoc name about))))
                               (and text (concat "  " (propertize text 'face 'completions-annotations))))))))
         (name (completing-read prompt (mapcar #'car alist) nil t nil nil default)))
    (cdr (assoc name alist))))

(defun org-truss--read-role (apex kind &optional current)
  "Read the role a supporting member of APEX plays in its pattern of KIND.
The roles that pattern names, those no supporting member plays yet
first, then none; CURRENT, the role it plays now, is the default.
Return the role, or nil for none."
  (let* ((roles (org-truss-supporting-role-ids apex kind))
         (open (mapcar #'cadr (seq-filter (lambda (gap) (eq (car gap) kind))
                                          (org-truss-gaps apex))))
         (alist (append (mapcar (lambda (r) (cons (org-truss-role-name r) r))
                                (seq-uniq (append open roles)))
                        (list (cons "(none)" nil)))))
    (org-truss--read-choice
     (format "Role in %s: " (org-truss-pattern-label (org-truss-member-pattern apex kind)))
     alist nil (and current (org-truss-role-name current)))))

(defun org-truss--read-roles (apex &optional current)
  "Read the roles a supporting member of APEX plays, one for each of its patterns.
CURRENT, (KIND . ROLE) each, are those it plays now, offered first.
Return them as (KIND . ROLE), for each pattern APEX has, ROLE nil for
none."
  (mapcar (lambda (kind)
            (cons kind (org-truss--read-role apex kind (alist-get kind current))))
          (seq-filter (lambda (kind) (org-truss-member-pattern apex kind))
                      org-truss-pattern-kinds)))

(defun org-truss--new-roles (apex gap)
  "Return the roles a new supporting member of APEX plays, as (KIND . ROLE).
GAP, (KIND . ROLE), when it is written on a role missing there, gives that
one.  A pattern of APEX with one role, or a telling pattern with a place
for what plays none, gives its own without asking; any other is asked."
  (delq nil
        (mapcar (lambda (kind)
                  (let ((roles (org-truss-supporting-role-ids apex kind)))
                    (cond ((eq kind (car gap)) gap)
                          ((org-truss--takes-any-p apex kind) nil)
                          ((null (cdr roles)) (and roles (cons kind (car roles))))
                          (t (let ((role (org-truss--read-role apex kind)))
                               (and role (cons kind role)))))))
                (seq-filter (lambda (kind) (org-truss-member-pattern apex kind))
                            org-truss-pattern-kinds))))

(defun org-truss--go (display &optional center)
  "Show the truss file with DISPLAY, at the member the line at point stands for.
Its text is shown, and the blocks in it open: a member is gone to so its
text can be read, and a comment block and the quotation are part of that
text, though `org-hide-block-startup' folds them.  The headings under it
are left as they were.  CENTER leaves a mark where point was in the file
and puts the member mid-window."
  (let ((item (org-truss--want (org-truss--item) 'member 'broken 'division)))
    (funcall display org-truss--source)
    (widen)
    (when center (push-mark))
    (goto-char (plist-get item :pos))
    (org-fold-show-context 'link-search)
    (org-fold-show-entry)
    (org-fold-region (point) (cdr (org-truss--text-bounds (point))) nil 'block)
    (when center (recenter (/ (window-height) 2)))))

(defun org-truss--follow (display &optional center)
  "Follow the link in a member's text at point, or go to the line's member.
DISPLAY shows the truss file.  A link drawn in a member's text is
followed as Org follows it from the file: one to a member goes to it
there, one to a source opens the source.  Elsewhere on the line, see
`org-truss--go'; CENTER as it takes it."
  (let ((link (get-text-property (point) 'org-truss-link)))
    (if (not link)
        (org-truss--go display center)
      (funcall display org-truss--source)
      (widen)
      (org-link-open-from-string link))))

(defun org-truss-board-visit ()
  "Go to the line's member in the truss file, in this window.
As RET does in the agenda: the file takes the board's window.  On a link
in a member's text, follow it instead: to the member it points to, or
the source."
  (interactive)
  (org-truss--follow #'pop-to-buffer-same-window))

(defun org-truss-board-visit-other-window ()
  "Go to the line's member in the truss file, in another window.
As TAB does in the agenda: a window already showing the file is used, or a
new one is made, and point goes there.  On a link in a member's text,
follow it instead, as `org-truss-board-visit' does."
  (interactive)
  (org-truss--follow (lambda (buffer)
                       (pop-to-buffer buffer '((display-buffer-reuse-window
                                                display-buffer-pop-up-window)
                                               (reuse-indirect . buffer))))
                     t))

(defvar-local org-truss--show-window nil
  "The window `org-truss-board-show' last showed the truss file in.")

(defun org-truss-board-show ()
  "Show the line's member in the truss file in another window, staying here.
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

;;;; The same member, where it is written and where it is linked to

(defun org-truss--member-pos (item)
  "Return the position of the member the line with ITEM names, or nil.
Where it is written or where it is linked to."
  (and (eq (plist-get item :type) 'member) (plist-get item :pos)))

(defun org-truss--head-p (item)
  "Non-nil when ITEM is a member's own line, not one it takes below it."
  (let ((key (plist-get item :key)))
    (and (plist-get item :words) (equal (org-truss--owner key) key))))

(defun org-truss--written-p (item)
  "Non-nil when ITEM is the line of a member where it is written.
In its division's tree, the member itself, not included."
  (and (org-truss--head-p item)
       (not (plist-get item :link))
       (memq (car (plist-get item :key)) '(member structure))))

(defun org-truss--link-p (item)
  "Non-nil when ITEM is the line of a member a link brings where it is.
An include link includes it there."
  (and (org-truss--head-p item) (plist-get item :link)))

(defvar org-truss--item-lines nil
  "The board's lines, as (START . ITEM), while one look over them is shared.
Bound by what asks of the board many times without changing it, so it
is read once; nil at any other time, when each asking reads the board.")

(defun org-truss--read-item-lines ()
  "Return (START . ITEM) for each line of the board with an item, in order."
  (save-excursion
    (goto-char (point-min))
    (let (found)
      (while (not (eobp))
        (let ((item (get-text-property (point) 'org-truss-item)))
          (when item
            (push (cons (point) item) found)))
        (forward-line 1))
      (nreverse found))))

(defun org-truss--lines-where (test)
  "Return (START . ITEM) for each line of the board whose ITEM passes TEST.
See `org-truss--item-lines'."
  (seq-filter (lambda (line) (funcall test (cdr line)))
              (or org-truss--item-lines (org-truss--read-item-lines))))

(defun org-truss--lines-naming (pos)
  "Return (START . ITEM) for each line of the board naming the member at POS.
A line whose words are an include link alone names the member it
includes too, when it stands for it; see `org-truss--brought-lines'."
  (org-truss--lines-where (lambda (item) (or (eql (org-truss--member-pos item) pos)
                                             (eql (plist-get item :alone) pos)))))

(defun org-truss--lines-using (pos)
  "Return (START . ITEM) for each member's line that links to the member at POS.
Standing on it or including it, as its :names say."
  (org-truss--lines-where (lambda (item) (and (org-truss--head-p item)
                                              (memq pos (plist-get item :names))))))

(defun org-truss--home-line (pos)
  "Return (START . ITEM) for the line the member at POS is drawn in full, or nil.
Where it is written; drawn as included, where it is written no more, the
first line Structure's links bring it to, `org-truss--chained'."
  (let ((heads (seq-filter (lambda (line) (org-truss--head-p (cdr line)))
                           (org-truss--lines-naming pos))))
    (or (seq-find (lambda (line) (org-truss--written-p (cdr line))) heads)
        (and (eq org-truss--board-order 'included)
             (seq-find (lambda (line) (or (eql (plist-get (cdr line) :alone) pos)
                                          (eq (car (plist-get (cdr line) :key)) 'link)))
                       heads)))))

(defun org-truss--lines-linked (item)
  "Return (START . ITEM) for each line linked to the member of ITEM, in order.
Those that stand on it or include it, those including it or standing on
it, but ITEM's own, and where each member it stands on or includes is
drawn in full: a link from it or to it, one step either way."
  (let ((pos (org-truss--member-pos item))
        (key (plist-get item :key))
        (names (plist-get item :names)))
    (and pos
         (seq-uniq
          (sort (append (org-truss--lines-using pos)
                        (seq-filter (lambda (line) (and (org-truss--link-p (cdr line))
                                                        (not (equal (plist-get (cdr line) :key) key))))
                                    (org-truss--lines-naming pos))
                        (delq nil (mapcar #'org-truss--home-line names)))
                (lambda (a b) (< (car a) (car b))))
          (lambda (a b) (= (car a) (car b)))))))

(defun org-truss--open-folds-over (pos)
  "Unfold every folded line of the board that hides the member at POS.
Return non-nil when one was."
  (let ((opened nil))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (let* ((item (get-text-property (point) 'org-truss-item))
               (at (plist-get item :pos)))
          (when (and (plist-get item :folded) at (< at pos)
                     (< pos (with-current-buffer org-truss--source
                              (org-with-wide-buffer
                               (goto-char at) (org-end-of-subtree t t) (point)))))
            (setf (alist-get (plist-get item :fold) org-truss--folds nil nil #'equal) 'open)
            (setq opened t)))
        (forward-line 1)))
    (when opened (org-truss-board-redraw))
    opened))

(defvar-local org-truss--same-from nil
  "The key of the line whose links `org-truss-board-same' goes round.")

(defun org-truss-board-same ()
  "Go round the lines linked to the member at point, or to where it is drawn.
Where it is drawn in full -- where it is written, or drawn as included
the first line a link brings it to -- go to the first line linked to it,
one step either way: one standing on it or including it, or where a
member it stands on or includes is drawn in full; see
`org-truss--lines-linked'.  Pressed again there, go to the next of them,
and round again.  On a line that shows a member anywhere else, as an
include link includes it, go to where it is drawn in full, unfolding
what hides it."
  (interactive)
  (let* ((item (org-truss--item))
         (pos (or (org-truss--member-pos item) (user-error "No member on this line")))
         (here (line-beginning-position))
         (from (and (eq last-command this-command) org-truss--same-from
                    (car (org-truss--lines-where
                          (lambda (other) (equal (plist-get other :key) org-truss--same-from))))))
         (round (and from (org-truss--lines-linked (cdr from))))
         (at (seq-position round here (lambda (line start) (= (car line) start))))
         (written (org-truss--home-line pos)))
    (cond
     (at
      (let ((next (mod (1+ at) (length round))))
        (goto-char (car (nth next round)))
        (message "Link %d of %d" (1+ next) (length round))))
     ((and written (= (car written) here))
      (let ((links (or (org-truss--lines-linked item)
                       (user-error "Nothing links to or from %s" (plist-get item :words)))))
        (setq org-truss--same-from (plist-get item :key))
        (goto-char (car (car links)))
        (message "Link 1 of %d" (length links))))
     (t
      (unless (or written (not (org-truss--open-folds-over pos)))
        (setq written (org-truss--home-line pos)))
      (goto-char (car (or written (user-error "%s is not written on the board"
                                              (plist-get item :words)))))))))

;;;; Lines lit with the line at point

(defun org-truss--light-same ()
  "Light the lines naming the member on the line at point, but that line.
Where else it is shown, and the lines linked to it one step either way;
see `org-truss--lines-linked'.  Nothing is done while point stays on the
line they were lit for."
  (let ((item (org-truss--item)))
    (unless (and item (eq item org-truss--same-item))
      (setq org-truss--same-item item)
      (mapc #'delete-overlay org-truss--same-overlays)
      (setq org-truss--same-overlays nil)
      (let ((pos (org-truss--member-pos item))
            (here (line-beginning-position))
            (org-truss--item-lines (org-truss--read-item-lines)))
        (when pos
          (dolist (line (seq-uniq (append (org-truss--lines-naming pos)
                                          (org-truss--lines-linked item))
                                  (lambda (a b) (= (car a) (car b)))))
            (unless (= (car line) here)
              (let ((overlay (make-overlay (car line)
                                           (save-excursion (goto-char (car line))
                                                           (min (point-max) (1+ (line-end-position)))))))
                (overlay-put overlay 'face 'org-truss-same)
                (push overlay org-truss--same-overlays)))))))))

;;;; Members opened where written, or where included

(defun org-truss--name-order ()
  "Say in the mode line where the board opens the members Structure includes."
  (setq mode-name (if (eq org-truss--board-order 'included) "Truss included" "Truss"))
  (force-mode-line-update))

(defun org-truss--goto-opened (pos)
  "Put point on the line where the member at POS is opened, if there is one.
As included, in Structure; as written, where it is written."
  (let ((opened (seq-find (lambda (line)
                            (let ((item (cdr line)))
                              (and (org-truss--head-p item)
                                   (if (eq org-truss--board-order 'included)
                                       (eq (car (plist-get item :key)) 'link)
                                     (org-truss--written-p item)))))
                          (org-truss--lines-naming pos))))
    (when opened
      (goto-char (car opened)))))

(defun org-truss-board-order ()
  "Open the members Structure includes where they are included, or where written.
As written, the board's first way, a member is opened where it is
written, with every member under it, and Structure has it on one line,
so the outline reads down the middle.  As included, it is opened under
the member of Structure that includes it instead, drawn just as it is
where it is written, and what its own include links include opened
there in turn, so the output document reads down Structure.  What a
member points to stays a link in its text.  What Structure brings so is
left out where it is written, and what is left there is not in the
output document; see `org-truss--order'.  What was folded or unfolded by hand starts again;
point stays on the member it was on, where it is opened now.  The mode
line says which way the board is drawn."
  (interactive)
  (let ((pos (org-truss--member-pos (org-truss--item))))
    (setq org-truss--board-order (if (eq org-truss--board-order 'included) 'written 'included)
          org-truss--folds (seq-remove (lambda (fold) (memq (car-safe (car fold)) '(member link)))
                                       org-truss--folds))
    (org-truss--name-order)
    (org-truss-board-redraw)
    (when pos
      (org-truss--goto-opened pos))
    (message "Members Structure includes are opened where they are %s"
             (if (eq org-truss--board-order 'included) "included" "written"))))

(defconst org-truss--taking-off
  '((logic . "take the logic off: its supporting members are no longer its reasons")
    (breakdown . "take the breakdown off: its supporting members are no longer its parts")
    (telling . "take the telling pattern off: its supporting members are told as written"))
  "What the board says beside taking off a pattern of each kind.")

(defun org-truss--pattern-about (id)
  "Return what the board says beside the pattern ID as it is offered.
ID is a pattern, or (none . KIND) for taking off the one of KIND."
  (if (eq (car-safe id) 'none)
      (alist-get (cdr id) org-truss--taking-off)
    (plist-get (org-truss-pattern id) :about)))

(defun org-truss--pattern-choices (member)
  "Return (LABEL . ID) for the patterns MEMBER can take, or take off.
Every pattern, of every kind; each kind it has can be taken off, as
\(none . KIND)."
  (append (mapcar (lambda (id) (cons (org-truss-pattern-label id) id))
                  (mapcan #'org-truss-patterns-of-kind org-truss-pattern-kinds))
          (delq nil (mapcar (lambda (kind)
                              (and (org-truss-member-pattern member kind)
                                   (cons (format "no %s" kind) (cons 'none kind))))
                            org-truss-pattern-kinds))))

(defun org-truss--read-pattern (member)
  "Read a pattern MEMBER can take, or one of its kinds to take off.
Return the pattern's id, or (none . KIND); see `org-truss--pattern-choices'."
  (let ((choices (org-truss--pattern-choices member)))
    (org-truss--read-choice
     "Pattern: " choices
     (mapcar (lambda (c) (cons (car c) (org-truss--pattern-about (cdr c)))) choices))))

(defun org-truss--apply-pattern (pos id in-structure)
  "Give the member at POS in this buffer the pattern ID, and its roles.
A heading, in its properties; an item, in #+attr_truss right in it.
ID is as `org-truss--read-pattern' returns it; IN-STRUCTURE is non-nil
when the member is Structure's.  What the pattern asks for and is not
there is put in, a member for each role, where the pattern lists it, to
be written over.  A telling pattern on a member of Structure takes the
headings under it into its roles first."
  (let ((item (save-excursion (goto-char pos) (not (org-at-heading-p)))))
    (if (eq (car-safe id) 'none)
        (if item
            (org-truss-set-item-pattern pos (cdr id) nil)
          (org-truss-set-pattern pos (cdr id) nil))
      (let ((kind (plist-get (org-truss-pattern id) :kind)))
        (cond ((and in-structure (eq kind 'telling) item)
               (user-error "A telling of Structure takes a heading"))
              ((and in-structure (eq kind 'telling))
               (org-truss-apply-telling pos id))
              (item (org-truss-set-item-pattern pos kind id))
              (t (org-truss-set-pattern pos kind id)))
        (let* ((member (org-truss-member-at (org-truss-read) pos))
               ;; An item with no list yet is read without the pattern
               ;; its line names: asked of it with none under it.
               (member (if (org-truss-member-pattern member kind)
                           member
                         (apply #'org-truss--make-member (list (intern (format ":%s" kind)) id))))
               (gaps (seq-filter (lambda (gap) (eq (car gap) kind))
                                 (org-truss-gaps member))))
          (if item
              (org-truss-add-role-items pos gaps)
            (org-truss-add-role-members pos gaps)))))))

(defun org-truss-board-pattern ()
  "Give the member at point a pattern: a division, or any member.
A logic says its supporting members are its reasons; a breakdown, its
parts; a telling pattern, how they are told.  What the pattern asks for
and is not there is put in, a member for each role, to be written over:
a deduction's premises, a 6W1H's parts, a PREP's reasons and examples.
A telling pattern on a member of Structure takes the headings under it
into its roles first.  `org-truss-apply-pattern' does the same from the
file."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member 'division))
         (pos (plist-get item :pos))
         (member (or (org-truss-member-at (org-truss-read org-truss--source) pos)
                     (user-error "Nothing to give a pattern to here")))
         (id (org-truss--read-pattern member)))
    (org-truss--editing
      (org-truss--apply-pattern pos id (org-truss-in-structure-p member)))))

(defun org-truss--pattern-alone (pos)
  "Return a marker at the heading to read alone for the heading at POS.
The nearest at or above POS with a pattern, else the heading at POS; in
a file that is no truss file, as the board of one heading reads it."
  (save-excursion
    (goto-char pos)
    (org-back-to-heading t)
    (let ((here (point))
          found)
      (while (and (not found)
                  (progn (when (org-truss--patterned-p) (setq found (point)))
                         (and (not found) (org-up-heading-safe)))))
      (copy-marker (or found here)))))

(defun org-truss-apply-pattern ()
  "Give the heading at point a pattern, in the file, as `p' on the board.
In a truss file, to the member the heading is.  In any other Org file, to
the heading, read as the board of one heading reads it: the nearest at
or above point with a pattern is read alone, and the heading at point is
in it.  What the pattern asks for and is not there is put in, a member
for each role, to be written over."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Not in an Org buffer"))
  (when (org-before-first-heading-p)
    (user-error "Not under a heading"))
  (let* ((pos (save-excursion (org-back-to-heading t) (point)))
         (org-truss--alone (unless (org-truss-file-p) (org-truss--pattern-alone pos)))
         (member (org-truss-member-at (org-truss-read) pos)))
    (unless member
      (user-error "Nothing to give a pattern to here"))
    (when (get-text-property pos 'org-dock)
      (user-error "This heading is out in a copy; give it the pattern there"))
    (let ((id (org-truss--read-pattern member)))
      (org-truss--apply-pattern pos id (org-truss-in-structure-p member))
      (message "%s" (if (eq (car-safe id) 'none)
                        (format "No %s pattern" (cdr id))
                      (org-truss-pattern-label id))))))

(defun org-truss-board-roles ()
  "Set the roles the member at point plays in the patterns of the one above.
One role for each pattern there: in its logic, in its breakdown, in its
telling pattern -- a reason that is also told as PREP's reason.  The roles
no supporting member plays yet are offered first."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (pos (plist-get item :pos))
         (model (org-truss-read org-truss--source))
         (member (org-truss-member-at model pos))
         (apex (org-truss-parent model member)))
    (unless (and apex (org-truss-apex-p apex))
      (user-error "The member above has no pattern to play a role in"))
    (let ((roles (org-truss--read-roles apex (org-truss-member-roles member))))
      (if (not (org-truss-item-p member))
          (org-truss--editing
            (pcase-dolist (`(,kind . ,role) roles)
              (org-truss-set-role pos kind role)))
        ;; An item names one role, before ::; one of a pattern of one
        ;; role it plays unnamed.
        (let ((named (seq-filter (lambda (r)
                                   (and (cdr r)
                                        (cdr (org-truss-pattern-roles
                                              (org-truss-member-pattern apex (car r))))))
                                 roles)))
          (when (cdr named)
            (user-error "An item names one role before ::; write it as a heading to play two"))
          (org-truss--editing
            (org-truss-set-item-role pos (cdar named))))))))

(defun org-truss--fold-line (key)
  "Return where the line that folds as KEY starts on the board, or nil."
  (save-excursion
    (goto-char (point-min))
    (let ((found (text-property-search-forward
                  'org-truss-item key
                  (lambda (key item) (equal key (plist-get item :fold))))))
      (and found (prop-match-beginning found)))))

(defun org-truss--fold-at (&optional nested)
  "Return the item of the line that is shown as the line at point is.
The line's own, when it is a member's, or the nearest such line above it
in the tree: its text, its grounds and its patterns are shown as its
member is.  With NESTED, the nearest that has something under it."
  (let* ((item (org-truss--item))
         (fits (lambda (item) (and (plist-get item :fold)
                                   (or (not nested) (> (or (plist-get item :nested) 0) 0))))))
    (if (funcall fits item)
        item
      (let ((key (butlast (plist-get item :key))) found)
        (while (and key (not found))
          (let ((at (org-truss--fold-line key)))
            (when (and at (funcall fits (get-text-property at 'org-truss-item)))
              (setq found (get-text-property at 'org-truss-item))))
          (setq key (butlast key)))
        (or found (user-error "Nothing to fold here"))))))

(defun org-truss--state (item)
  "Return how the line with ITEM is shown: `folded', `open' or `whole'.
See `org-truss--folds'."
  (or (alist-get (plist-get item :fold) org-truss--folds nil nil #'equal)
      (if (plist-get item :folded) 'folded 'open)))

(defun org-truss--key-under-p (key above)
  "Non-nil when the line keyed KEY is drawn under the line keyed ABOVE.
A member's key runs on from the line it is under; a member of
Structure's path from the member above; a link's names the line it is
drawn under."
  (cond ((equal key above) nil)
        ((and (> (length key) (length above))
              (equal (seq-take key (length above)) above)))
        ((and (eq (car key) 'structure) (eq (car above) 'structure))
         (let ((path (cadr key)) (up (cadr above)))
           (and (> (length path) (length up)) (equal (seq-take path (length up)) up))))
        ((memq (car key) '(link ground))
         (let ((holder (if (memq (car-safe (cadr key)) '(member link structure ground))
                           (cadr key)
                         (list 'structure (cadr key)))))
           (or (equal holder above) (org-truss--key-under-p holder above))))))

(defun org-truss--drawn-folds ()
  "Return the items of the lines of the board that are shown as set, top to bottom.
Each member's own line, and each line a check lists; see
`org-truss--folds'."
  (save-excursion
    (goto-char (point-min))
    (let (found)
      (while (not (eobp))
        (let ((item (org-truss--item)))
          (when (and (plist-get item :fold) (equal (plist-get item :fold) (plist-get item :key)))
            (push item found)))
        (forward-line 1))
      (nreverse found))))

(defun org-truss--set-folds (keys state)
  "Set the lines keyed KEYS to STATE for the next draw; see `org-truss--folds'."
  (dolist (key keys)
    (setf (alist-get key org-truss--folds nil nil #'equal) state)))

(defun org-truss--show-all (state &optional above)
  "Show every line of the board as STATE, `open' or `whole'.
Or the line keyed ABOVE and every line under it.  A line opened can
bring lines that start folded -- a member drawn where an include link
includes it -- so the board is drawn again until none is left, or until
it has gone ten levels down."
  (let ((n 0) left)
    (while (and (< n 10)
                (setq left (mapcar (lambda (item) (plist-get item :fold))
                                   (seq-filter (lambda (item)
                                                 (and (not (eq (org-truss--state item) state))
                                                      (or (null above)
                                                          (equal (plist-get item :fold) above)
                                                          (org-truss--key-under-p (plist-get item :fold)
                                                                                  above))))
                                               (org-truss--drawn-folds)))))
      (org-truss--set-folds left state)
      (org-truss-board-redraw)
      (setq n (1+ n)))))

(defun org-truss-board-cycle (&optional all)
  "Cycle the line at point: folded, its text and what is right under it, all.
As TAB cycles a heading in Org.  A folded line, one line cut short, opens
to show its words whole and its text, with what is right under it, each
of those folded; pressed again, everything under it is shown so too;
again, it folds.  On a line with nothing under it, its words and text are
shown whole, or it is one line again.  On a line a member brings below
it -- its text, its patterns -- the member's line cycles.  A folded line says how many it hides.  With a prefix argument
ALL, as \\[universal-argument] TAB in Org, the whole board cycles instead;
see `org-truss-board-cycle-all'."
  (interactive "P")
  (org-truss--reading-once
    (if all
        (org-truss--cycle-all)
      (org-truss--cycle-line))))

(defun org-truss--cycle-line ()
  "Cycle the line at point, as `org-truss-board-cycle' says."
  (let* ((line (org-truss--fold-at))
         (key (plist-get line :fold))
         (state (org-truss--state line))
         (under (lambda () (seq-filter (lambda (item) (org-truss--key-under-p (plist-get item :fold) key))
                                       (org-truss--drawn-folds)))))
    (cond ((zerop (or (plist-get line :nested) 0))
           (org-truss--set-folds (list key) (if (eq state 'whole) 'open 'whole))
           (org-truss-board-redraw)
           (message (if (eq state 'whole) "One line" "Whole")))
          ((eq state 'folded)
           (org-truss--set-folds (list key) 'whole)
           (org-truss-board-redraw)
           (org-truss--set-folds (mapcar (lambda (item) (plist-get item :fold)) (funcall under)) 'folded)
           (org-truss-board-redraw)
           (message "Children"))
          ((or (not (eq state 'whole))
               (seq-some (lambda (item) (not (eq (org-truss--state item) 'whole))) (funcall under)))
           (org-truss--show-all 'whole key)
           (message "Subtree"))
          (t
           (org-truss--set-folds (list key) 'folded)
           (org-truss-board-redraw)
           (message "Folded")))
    (goto-char (or (org-truss--fold-line key) (point)))))

(defun org-truss-board-cycle-all ()
  "Cycle the whole board: folded, every line open, every line whole.
As S-TAB does in Org, in three steps: overview, every member folded down
to the divisions; contents, every member open on one line; and everything,
every line whole with its text."
  (interactive)
  (org-truss--reading-once
    (org-truss--cycle-all)))

(defun org-truss--cycle-all ()
  "Cycle the whole board, as `org-truss-board-cycle-all' says."
  (let ((key (plist-get (org-truss--item) :key))
        (drawn (org-truss--drawn-folds)))
    (cond ((seq-every-p (lambda (item) (eq (org-truss--state item) 'whole)) drawn)
           (org-truss--set-folds (mapcar (lambda (item) (plist-get item :fold)) drawn) 'folded)
           (org-truss-board-redraw)
           (message "Overview"))
          ((seq-some (lambda (item) (eq (org-truss--state item) 'folded)) drawn)
           (org-truss--show-all 'open)
           (message "Contents"))
          (t
           (org-truss--show-all 'whole)
           (message "Show all")))
    (let ((found (and key (save-excursion
                            (goto-char (point-min))
                            (text-property-search-forward
                             'org-truss-item key
                             (lambda (k item) (equal k (plist-get item :key))))))))
      (when found (goto-char (prop-match-beginning found))))))

(defun org-truss-board-fold ()
  "Fold what is under the member at point, or unfold it.
Its supporting members and the members its include links include.  On a
line with nothing under it, what it is under.  A folded line says how
many it hides.  \\[org-truss-board-cycle] cycles it as Org's TAB does
instead."
  (interactive)
  (let* ((line (org-truss--fold-at t))
         (key (plist-get line :fold)))
    (org-truss--set-folds (list key) (if (plist-get line :folded) 'open 'folded))
    (org-truss-board-redraw)
    (goto-char (or (org-truss--fold-line key) (point)))))

(defun org-truss-board-edit ()
  "Take the member of the line at point out, to be written in beside the board.
The heading and everything under it go into a copy of their own, by
org-dock, the headings under it folded so that its own text is in view,
and the heading cannot change in the file meanwhile.  As in a capture
buffer, \\<org-dock-mode-map>\\[org-dock-finish] writes it back and saves
the file, and \\[org-dock-abort] lets it go, leaving the heading as it was.
Back on the board, it draws again.  On a member written as an item of a
list, the heading whose text holds it, at the item."
  (interactive)
  (let* ((pos (plist-get (org-truss--want (org-truss--item) 'member 'broken 'division)
                         :pos))
         (holder (org-truss--item-holder pos)))
    (if holder
        (org-truss--edit holder pos)
      (org-truss--edit pos))))

(defun org-truss--text-end (pos)
  "Return where text is written in the heading at POS: after its own text.
On the line after the last of it -- unless that line is a heading under
it, where what is typed would go into the heading; then at the end of the
line before."
  (save-excursion
    (let ((end (save-excursion (goto-char pos) (org-end-of-subtree t t) (point))))
      (goto-char (cdr (org-truss--text-bounds pos)))
      (skip-chars-backward " \t\n")
      (forward-line 1)
      (if (and (< (point) end) (org-at-heading-p))
          (1- (point))
        (point)))))

(defun org-truss--fold-copy ()
  "Show this copy's heading with its own text, the headings under it folded.
Its blocks and drawers are open, as they are part of what it says."
  (save-excursion
    (goto-char (point-min))
    (when (org-at-heading-p)
      (org-fold-hide-subtree)
      (org-fold-show-entry)
      (org-fold-show-children)
      (org-fold-show-all '(blocks drawers)))))

(defun org-truss-check-command (file)
  "Return the command line that checks FILE, as this Emacs runs it.
With org-moor when it is loaded, so that its links are checked too."
  (let* ((moor (featurep 'org-moor))
         (dir-of (lambda (library)
                   (shell-quote-argument
                    (directory-file-name (file-name-directory (locate-library library))) t))))
    (format "%s --batch -L %s -L %s -L %s%s -l org-truss%s -f org-truss-batch-check %s"
            (shell-quote-argument (expand-file-name invocation-name invocation-directory) t)
            (funcall dir-of "org-truss") (funcall dir-of "org-dock") (funcall dir-of "org-item-tags")
            (if moor (concat " -L " (funcall dir-of "org-moor")) "")
            (if moor " -l org-moor" "")
            (shell-quote-argument file t))))

(defun org-truss--dock-patterns (copy)
  "Return the patterns of the headings in the buffer COPY, each once, in order."
  (with-current-buffer copy
    (org-with-wide-buffer
     (goto-char (point-min))
     (let ((case-fold-search t)
           found)
       (while (re-search-forward
               "^[ \t]*:TRUSS_\\(?:LOGIC\\|BREAKDOWN\\|TELLING\\):[ \t]*\\(\\S-+\\)" nil t)
         (let ((id (intern (match-string 1))))
           (when (org-truss-pattern id)
             (cl-pushnew id found))))
       (nreverse found)))))

(defun org-truss--dock-plays (copy origin line)
  "Return what the copy's first heading plays in the patterns above it.
COPY is the copy's buffer, ORIGIN the buffer it came from and LINE the
line of ORIGIN the copy starts at.  As (WORDS . PLAYS): the words of the
heading right above, and each (PATTERN . ROLE) of it the copy's heading
plays a role of; nil when it plays none."
  (let ((roles (with-current-buffer copy
                 (org-with-wide-buffer
                  (goto-char (point-min))
                  (when (or (org-at-heading-p) (outline-next-heading))
                    (mapcar (lambda (kind)
                              (cons kind (org-entry-get nil (org-truss-role-property (car kind)))))
                            org-truss-pattern-properties))))))
    (with-current-buffer origin
      (org-with-wide-buffer
       (goto-char (point-min))
       (forward-line (1- line))
       (when (and (org-at-heading-p) (org-up-heading-safe))
         (let ((plays (delq nil
                            (mapcar (lambda (kind)
                                      (let* ((id (org-entry-get nil (cdar kind)))
                                             (id (and id (intern id)))
                                             (role (and (cdr kind) (intern (cdr kind)))))
                                        (and (assq role (org-truss-pattern-roles id))
                                             (cons id role))))
                                    roles))))
           (and plays (cons (org-get-heading t t t t) plays))))))))

(defun org-truss-dock-request (request)
  "Tell an agent how the copy REQUEST names is written, and how to check it.
REQUEST is the plist `org-dock-agent-function' gets.  Said of a copy out
of a truss file, and of one out of any Org file whose headings, or the
heading right above the copy, have patterns; nil otherwise.  The same
words whatever was taken out: the patterns there, with what the copy's
heading plays in the one above it; where the rest of a truss file's rules
are; and the command that checks the copy, written back where it came
from.  Each only when it has something to say."
  (let* ((copy (find-file-noselect (plist-get request :copy)))
         (file (plist-get (org-dock-copy-origin (plist-get request :copy)) :file))
         (origin (if file (find-file-noselect file) (get-buffer (plist-get request :origin))))
         (lines (plist-get request :lines))
         (plays (and origin lines (not (plist-get request :whole))
                     (org-truss--dock-plays copy origin (car lines))))
         (ids (seq-uniq (append (mapcar #'car (cdr plays)) (org-truss--dock-patterns copy))))
         (truss (and origin (org-truss-file-p origin))))
    (when (or ids truss)
      (concat
       "## Truss\n\n"
       (when ids
         (concat
          "A member's TRUSS_LOGIC, TRUSS_BREAKDOWN or TRUSS_TELLING names its pattern:\n"
          "what its supporting members, the members right under it, are to it.  A\n"
          "supporting member written as a heading names its role in the same property\n"
          "with _ROLE after it.  The patterns here, with their roles and, in brackets,\n"
          "the words of a member put in for a role and not written yet:\n\n"
          (mapconcat (lambda (id)
                       (let ((pattern (org-truss-pattern id)))
                         (format "- %s (%s): %s.\n  Roles: %s" id
                                 (alist-get (plist-get pattern :kind) org-truss-pattern-properties)
                                 (plist-get pattern :about)
                                 (mapconcat (lambda (role)
                                              (format "%s [%s]" role (org-truss-role-label role)))
                                            (mapcar #'car (plist-get pattern :roles))
                                            ", "))))
                     ids "\n")
          "\n\n"
          (when plays
            (format "The copy's heading plays %s of %S, above the copy.\n\n"
                    (mapconcat (lambda (play) (format "%s in the %s" (cdr play) (car play)))
                               (cdr plays) ", and ")
                    (car plays)))
          "- Under a member with a pattern, write a supporting member for each role:\n"
          "  its words one sentence that states what plays the role.  Write over words\n"
          "  that are still the ones in brackets.\n"
          "- In a TRUSS_LOGIC truss, give each supporting member grounds: a\n"
          "  #+begin_quote, or a link in its text to a member, [[m3]], or to a\n"
          "  source.  It needs none as the apex member of a TRUSS_LOGIC truss of its\n"
          "  own, or with the tag :assumption:.\n\n"))
       (when truss
         "The other rules of the file are in its guide.\n\n")
       (when file
         (concat "After editing, check the copy, not the file it came from:\n\n"
                 "    " (org-truss-check-command (plist-get request :copy)) "\n"))))))

(add-hook 'org-dock-request-functions #'org-truss-dock-request 20)

;; The same from the package's autoloads, so that a heading with patterns,
;; in any Org file, says so when it is handed to an agent before anything of
;; org-truss has been used.
;;;###autoload (autoload 'org-truss-dock-request "org-truss")
;;;###autoload (with-eval-after-load 'org-dock (add-hook 'org-dock-request-functions #'org-truss-dock-request 20))

(defun org-truss--edit (pos &optional body session)
  "Take the heading at POS out by org-dock, to be written in beside the board.
With BODY, point goes below the heading and its drawers, where its text is
written, or to BODY itself when it is a position; otherwise to the heading.

SESSION, when the heading was written just now or a block put in for it,
says how to take that back when the copy is let go: :new, non-nil for a
heading written just now, which goes; :undo, a function taking back the
rest; :hash and :modified, the truss file's buffer before, made
unmodified again when it holds what it held.  Writing the copy back saves
the file."
  (let* ((source org-truss--source)
         (copy
          (with-current-buffer source
            (org-with-wide-buffer
             (let ((head (copy-marker pos))
                   (at (cond ((not body) nil)
                             ((number-or-marker-p body) body)
                             (t (org-truss--text-end pos)))))
               (org-dock-heading
                pos :at at :display nil
                :finish (lambda (_beg _end)
                          (set-marker head nil)
                          (when buffer-file-name (save-buffer)))
                :abort (lambda ()
                         (org-with-wide-buffer
                          (if (plist-get session :new)
                              (progn (goto-char head)
                                     (delete-region (point) (save-excursion
                                                              (org-end-of-subtree t t)
                                                              (point)))))
                          (when-let* ((undo (plist-get session :undo)))
                            (funcall undo)))
                         (set-marker head nil)
                         (when (and session (not (plist-get session :modified))
                                    (equal (buffer-hash) (plist-get session :hash)))
                           (set-buffer-modified-p nil)))))))))
    (with-current-buffer copy (org-truss--fold-copy))
    (pop-to-buffer copy '((display-buffer-reuse-window display-buffer-pop-up-window)))))

(defun org-truss--goto-words (words &optional structure)
  "Put point on the first line of the board for the member of WORDS, if any.
One Structure can include, or with STRUCTURE, a member of Structure."
  (let ((found (save-excursion
                 (goto-char (point-min))
                 (text-property-search-forward
                  'org-truss-item words
                  (lambda (words item) (and (eq (plist-get item :type) 'member)
                                            (eq (and (plist-get item :structure) t) (and structure t))
                                            (equal words (plist-get item :words))))))))
    (when found
      (goto-char (prop-match-beginning found)))))

(defun org-truss-board-new ()
  "Write a new member, and open it beside the board to be written.
It goes last under what the line at point is:

- a member, or a division -- Brief, Subject, Message;
- a missing role of one, playing that role;
- a member of Structure: last under Message, included by it;
- anything else: last under Message.

Under a member with patterns it plays a role in each: the one a pattern
has, when it has one alone, else the one asked for.  The entry opens as
`org-truss-board-edit' opens one, and aborting it takes the new member
away."
  (interactive)
  (when (and (org-truss--in-structure-item-p (org-truss--item)) (plist-get (org-truss--item) :gap))
    (user-error "A member of Structure plays this; write it in the file"))
  (let* ((item (org-truss--item))
         (model (org-truss-read org-truss--source))
         (message (with-current-buffer org-truss--source (org-truss--division-pos "message")))
         (in-structure (org-truss--in-structure-item-p item))
         (over (and (not in-structure)
                    (memq (plist-get item :type) '(member division))
                    (let ((m (org-truss-member-at model (plist-get item :pos))))
                      (and m (or (not (org-truss-member-is-division m))
                                 (memq (org-truss-member-division m) '(brief subject message)))
                           m))))
         (parent (cond (over (org-truss-member-pos over))
                       (message)
                       (t (user-error "No Message division to write it in"))))
         (includer (and in-structure (plist-get item :pos)))
         (words (string-trim (read-string "New member: ")))
         (roles (and over (org-truss--new-roles over (plist-get item :gap))))
         ;; Included by a member of Structure, it is linked to from the start.
         (id (and includer (with-current-buffer org-truss--source (org-truss--next-id))))
         (props (org-truss--role-props roles))
         (session (with-current-buffer org-truss--source
                    (list :new t :hash (buffer-hash) :modified (buffer-modified-p))))
         at)
    (when (string-empty-p words)
      (user-error "A member needs words"))
    (when (org-truss-member-by-words model words)
      (user-error "A member already says %s" words))
    ;; What it is written under is unfolded, so the board can go to it.
    ;; A missing role's line is keyed under its member's, by (gap KIND ROLE).
    (let ((fold (and over (not (org-truss-member-is-division over))
                     (if (plist-get item :gap)
                         (butlast (plist-get item :key) 3)
                       (plist-get item :key)))))
      (when fold
        (setf (alist-get fold org-truss--folds nil nil #'equal) 'open)))
    (org-truss--editing
      (let ((includer (and includer (copy-marker includer))))
        (setq at (org-truss-add-heading parent (if id (format "<<%s>>%s" id words) words) props))
        (when includer
          (org-truss-add-include includer id)
          (setq session (plist-put session :undo
                                   (lambda ()
                                     (org-truss-remove-include includer id)
                                     (set-marker includer nil)))))))
    (org-truss--goto-words words)
    (org-truss--edit (marker-position at) t session)
    (set-marker at nil)))

(defun org-truss--fill-view (buffer model)
  "Put the output document MODEL describes into BUFFER, keeping its point."
  (with-current-buffer buffer
    (let ((inhibit-read-only t)
          (at (point)))
      (erase-buffer)
      (insert (org-truss-render-document model))
      (unless (derived-mode-p 'org-mode)
        (org-mode)
        (view-mode 1))
      (org-fold-show-all)
      ;; Its links are read from the truss file's directory, as they are
      ;; written there, so a picture it shows is found.
      (setq default-directory (org-truss--model-directory model))
      (when (display-images-p)
        (org-display-inline-images nil t))
      (goto-char (min at (point-max))))))

(defun org-truss-board-view ()
  "Show the output document in another window.
As \\[org-truss-board-export] would write it.  Nothing is written.  While
it is shown, the board keeps it current."
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

(defun org-truss-board-guide ()
  "Say in the echo area what the member of the line at point is for.
A division's guide, or that of a role of Brief's or Subject's breakdown --
on the member playing it, or on the line of the role missing -- and for
any other member its patterns and the roles it plays.  The rules of the
file are its guide, in the drawer at its head."
  (interactive)
  (let* ((item (org-truss--item))
         (model (org-truss-read org-truss--source))
         (member (and (plist-get item :pos) (org-truss-member-at model (plist-get item :pos))))
         (gap (plist-get item :gap))
         (text (cond ((and member gap (org-truss-member-is-division member))
                      (org-truss-division-guide (org-truss-member-division member) (cdr gap)))
                     (member (org-truss-guide-of model member)))))
    (message "%s" (or text "Nothing is said of this line; the file's rules are in the guide at its head"))))

(defun org-truss-board-export ()
  "Write the output document."
  (interactive)
  (let ((written (org-truss-export-buffer org-truss--source)))
    (message "org-truss: wrote %s" (mapconcat #'abbreviate-file-name written ", "))))

(provide 'org-truss-board)

;;; org-truss-board.el ends here

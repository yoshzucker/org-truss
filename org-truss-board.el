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
;; goes there.  How it is drawn is in org-truss-draw.el; here are its mode,
;; its buffer and its commands.
;;
;; The board's own words are English whatever `org-truss-language' says, so
;; a label, a heading or a title in another language is plainly the file's.

;;; Code:

(require 'org-truss-core)
(require 'org-truss-edit)
(require 'org-truss-guide)
(require 'org-truss-export)
(require 'org-truss-draw)

(defvar-local org-truss--folds nil
  "Lines of this board folded or unfolded by hand, as (KEY . open|closed).
A line not here is folded or not as `org-truss-board-fold-limit' says.")

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

(defvar-local org-truss--view nil
  "The buffer showing this board's document, if one has been opened.")

(defvar-local org-truss--board-order 'written
  "Where this board opens a member a section lists: `written' or `told'.
See `org-truss--order'.")

(defcustom org-truss-board-highlight t
  "Non-nil to light the line at point on the board, and the lines like it.
The line at point with `hl-line-mode'; the other lines naming the member
on it -- where it is written, where it is called, wherever else it shows
-- in the face `org-truss-same'."
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
\\[org-truss-board-show] show  \\[org-truss-board-same] written/called  \
\\[org-truss-board-order] written/told order  \\[org-truss-board-entry-text] entry text  \
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
                  (org-truss--order org-truss--board-order)
                  (org-truss--wrapping org-truss--wraps)
                  (org-truss--images (display-images-p (and window (window-frame window)))))
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
        (forward-line (1- line))))
    ;; The lines lit went with the text; light them again.
    (setq org-truss--same-overlays nil
          org-truss--same-item nil)
    (when org-truss-board-highlight
      (org-truss--light-same))))

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
    (define-key map (kbd "=") #'org-truss-board-same)
    (define-key map (kbd "O") #'org-truss-board-order)
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
    (when (and (or (null org-truss-board-middle-width)
                   (and (or org-truss--entry-text org-truss--wraps)
                        (null org-truss-board-right-width)))
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
  "Read roles with PROMPT, offering CURRENT as the default.
PARENT is the section or member the roles are taken under: the roles its
patterns ask for come first, those nothing fills yet before the rest, then
every other role."
  (let* ((asked (and parent (org-truss-asked-roles parent)))
         (open (and parent (mapcar #'car (org-truss-gaps parent))))
         (alist (mapcar (lambda (r) (cons (org-truss-role-name r) r))
                        (seq-uniq (append open asked (mapcar #'car org-truss-roles)))))
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
and puts the heading mid-window.  On a line marked =→=, where the member
is used, that is the section or the member that uses it."
  (let ((item (org-truss--want (org-truss--item) 'section 'member 'broken 'brief 'use)))
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

;;;; The same member, where it is written and where it is called

(defun org-truss--member-pos (item)
  "Return the position of the member the line with ITEM names, or nil."
  (and (eq (plist-get item :type) 'member) (plist-get item :pos)))

(defun org-truss--head-p (item)
  "Non-nil when ITEM is a member's own line, not one it takes below it."
  (let ((key (plist-get item :key)))
    (and (plist-get item :label) (equal (org-truss--owner key) key))))

(defun org-truss--written-p (item)
  "Non-nil when ITEM is the line of a member where it is written.
In the subject or the members, as the member itself, not called."
  (and (org-truss--head-p item)
       (not (plist-get item :link)) (not (plist-get item :ground))
       (memq (car (plist-get item :key)) '(member field))))

(defun org-truss--call-p (item)
  "Non-nil when ITEM is the line of a call to a member: a link, a ground."
  (and (org-truss--head-p item)
       (or (plist-get item :link) (plist-get item :ground))))

(defun org-truss--lines-naming (pos)
  "Return (START . ITEM) for each line of the board naming the member at POS."
  (save-excursion
    (goto-char (point-min))
    (let (found)
      (while (not (eobp))
        (let ((item (get-text-property (point) 'org-truss-item)))
          (when (eql (org-truss--member-pos item) pos)
            (push (cons (point) item) found)))
        (forward-line 1))
      (nreverse found))))

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

(defvar-local org-truss--last-call nil
  "The key of the call `org-truss-board-same' last went from to a member.")

(defun org-truss-board-same ()
  "Go to the same member: where it is written, or where it is called.
On a line that calls a member -- a section's link, [[#m9]], or a ground --
or that shows it anywhere else, go to where it is written, #m9, in the
subject or the members, unfolding what hides it.  There, go to the next
line that calls it, after the one come from, and round again."
  (interactive)
  (let* ((item (org-truss--item))
         (pos (or (org-truss--member-pos item) (user-error "No member on this line")))
         (lines (org-truss--lines-naming pos))
         (written (seq-find (lambda (line) (org-truss--written-p (cdr line))) lines)))
    (if (and written (= (car written) (line-beginning-position)))
        (let* ((calls (seq-filter (lambda (line) (org-truss--call-p (cdr line))) lines))
               (last (seq-position calls org-truss--last-call
                                   (lambda (line key) (equal (plist-get (cdr line) :key) key))))
               (next (if last (mod (1+ last) (max 1 (length calls))) 0))
               (call (nth next calls)))
          (unless call
            (user-error "Nothing calls %s" (plist-get item :label)))
          (setq org-truss--last-call (plist-get (cdr call) :key))
          (goto-char (car call))
          (message "Call %d of %d" (1+ next) (length calls)))
      (when (org-truss--call-p item)
        (setq org-truss--last-call (plist-get item :key)))
      (unless (or written (not (org-truss--open-folds-over pos)))
        (setq written (seq-find (lambda (line) (org-truss--written-p (cdr line)))
                                (org-truss--lines-naming pos))))
      (goto-char (car (or written (user-error "%s is not written on the board"
                                              (plist-get item :label))))))))

;;;; Lines lit with the line at point

(defun org-truss--light-same ()
  "Light the lines naming the member on the line at point, but that line.
Nothing is done while point stays on the line they were lit for."
  (let ((item (org-truss--item)))
    (unless (and item (eq item org-truss--same-item))
      (setq org-truss--same-item item)
      (mapc #'delete-overlay org-truss--same-overlays)
      (setq org-truss--same-overlays nil)
      (let ((pos (org-truss--member-pos item))
            (here (line-beginning-position)))
        (when pos
          (dolist (line (org-truss--lines-naming pos))
            (unless (= (car line) here)
              (let ((overlay (make-overlay (car line)
                                           (save-excursion (goto-char (car line))
                                                           (min (point-max) (1+ (line-end-position)))))))
                (overlay-put overlay 'face 'org-truss-same)
                (push overlay org-truss--same-overlays)))))))))

;;;; Members opened where written, or where told

(defun org-truss--name-order ()
  "Say in the mode line where the board opens the members a section lists."
  (setq mode-name (if (eq org-truss--board-order 'told) "Truss told" "Truss"))
  (force-mode-line-update))

(defun org-truss--goto-opened (pos)
  "Put point on the line where the member at POS is opened, if there is one.
As told, in the structure; as written, where it is written."
  (let ((opened (seq-find (lambda (line)
                            (let ((item (cdr line)))
                              (and (org-truss--head-p item)
                                   (if (eq org-truss--board-order 'told)
                                       (eq (car (plist-get item :key)) 'link)
                                     (org-truss--written-p item)))))
                          (org-truss--lines-naming pos))))
    (when opened
      (goto-char (car opened)))))

(defun org-truss-board-order ()
  "Open the members a section lists where they are told, or where written.
As written, the board's first way, a member is opened where it is written
-- with what is nested under it, where it is used and what it stands on
-- and the structure lists it on one line, so the story reads down the
middle.  As told, it is opened under its section instead, with all of
that, so the document reads down the right beside the logic it rests on,
and where it is written it is one line.  A member of the subject stays
open where it is written, since the document tells its words alone.
What was folded or unfolded by hand starts again; point stays on the
member it was on, where it is opened now.  The mode line says which way
the board is drawn."
  (interactive)
  (let ((pos (org-truss--member-pos (org-truss--item))))
    (setq org-truss--board-order (if (eq org-truss--board-order 'told) 'written 'told)
          org-truss--folds (seq-remove (lambda (fold) (memq (car-safe (car fold)) '(member link)))
                                       org-truss--folds))
    (org-truss--name-order)
    (org-truss-board-redraw)
    (when pos
      (org-truss--goto-opened pos))
    (message "Members a section lists are opened where they are %s"
             (if (eq org-truss--board-order 'told) "told" "written"))))

(defconst org-truss--taking-off
  '((logic . "take the logic pattern off: a member's support is its reasons")
    (aspects . "take the aspects off: nothing need be covered")
    (telling . "take the telling pattern off: told as conclusion first tells it"))
  "What the board says beside taking off a pattern of each kind.")

(defun org-truss--pattern-about (id)
  "Return what the board says beside the pattern ID as it is offered.
ID is a pattern, or (none . KIND) for taking off the one of KIND."
  (if (eq (car-safe id) 'none)
      (alist-get (cdr id) org-truss--taking-off)
    (let ((places (org-truss-pattern-places id)))
      (if places
          (mapconcat (lambda (place) (org-truss-role-name (car place))) places " / ")
        (plist-get (org-truss-pattern id) :about)))))

(defun org-truss--pattern-choices (cluster)
  "Return (LABEL . ID) for the patterns CLUSTER can take, or take off.
Every logic pattern; the aspects, when its logic pattern is one that takes
them; and a telling pattern, unless it is a finding, which is not told,
only listed.  The brief and the subject take aspects alone: their fields
are what must be there, and nothing of them is told or argued.  Each kind
it has can be taken off, as (none . KIND)."
  (let* ((part (org-truss-part-p cluster))
         (logic (org-truss-cluster-logic cluster))
         (told (and (not part)
                    (or (org-truss-section-p cluster) (not (org-truss-finding-p cluster))))))
    (append (mapcar (lambda (id) (cons (org-truss-pattern-label id) id))
                    (append (and (not part) (org-truss-patterns-of-kind 'logic))
                            (and (org-truss-aspects-allowed-p logic)
                                 (org-truss-patterns-of-kind 'aspects))
                            (and told (org-truss-patterns-of-kind 'telling))))
            (delq nil (mapcar (lambda (kind)
                                (and (alist-get kind (list (cons 'logic logic)
                                                           (cons 'aspects (org-truss-cluster-aspects cluster))
                                                           (cons 'telling (org-truss-cluster-telling cluster))))
                                     (cons (format "no %s" kind) (cons 'none kind))))
                              '(logic aspects telling))))))

(defun org-truss-board-pattern ()
  "Apply a pattern to the cluster at point: a member, a section, the structure,
the brief or the subject.
A logic pattern says how what is right under it is joined to it -- why it
holds, or what it is made of; aspects say what must all be there; a
telling pattern, how it is told.  What the pattern asks for and is not
there is put in, a heading for each place, to be written over: a
deduction's premises, a 6W1H's aspects, a PREP's reasons and examples; on
the brief or the subject, a field.  A telling pattern on a section takes
the sections there into its places first.  Logic that takes no aspects
takes them off."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'section 'member 'brief))
         (section (eq (plist-get item :type) 'section))
         (pos (plist-get item :pos))
         (cluster (or (let ((cluster (org-truss-cluster-at (org-truss-read org-truss--source) pos)))
                        (and (not (org-truss-field-p cluster)) cluster))
                      (user-error "Nothing to apply a pattern to here")))
         (choices (org-truss--pattern-choices cluster))
         (id (org-truss--read-choice
              "Pattern: " choices
              (mapcar (lambda (c) (cons (car c) (org-truss--pattern-about (cdr c)))) choices))))
    (org-truss--editing
      (if (eq (car-safe id) 'none)
          (org-truss-set-pattern pos (cdr id) nil)
        (let ((kind (plist-get (org-truss-pattern id) :kind)))
          (if (and section (eq kind 'telling))
              (org-truss-apply-section-telling pos id)
            (org-truss-set-pattern pos kind id))
          (when (and (eq kind 'logic) (not (org-truss-aspects-allowed-p id)))
            (org-truss-set-pattern pos 'aspects nil))
          (let* ((cluster (org-truss-cluster-at (org-truss-read) pos))
                 (asks (if (eq kind 'telling)
                           (mapcar #'car (org-truss-places-under cluster))
                         (plist-get (org-truss-pattern id) :roles)))
                 (gaps (seq-filter (lambda (gap) (memq (car gap) asks))
                                   (org-truss-gaps cluster))))
            (if (org-truss-part-p cluster)
                (pcase-dolist (`(,role . ,short) gaps)
                  (dotimes (_ short)
                    (set-marker (org-truss-add-field pos role) nil)))
              (org-truss-add-places pos gaps section))))))))

(defun org-truss-board-new-section ()
  "Add a section under the section at point.
On a gap -- a place the section's pattern asks for and no section below
fills -- the new section fills it.  On a gap of the brief or the subject,
a field their pattern asks for and none fills, a new field fills it."
  (interactive)
  (let ((item (org-truss--item)))
    (if (and (eq (plist-get item :type) 'brief) (plist-get item :gap))
        (org-truss--editing
          (set-marker (org-truss-add-field (plist-get item :pos) (plist-get item :gap)) nil))
      (let* ((item (org-truss--want item 'section))
             (gap (plist-get item :gap))
             (roles (if gap (list gap)
                      (org-truss--read-roles "Answers (empty for none): " nil
                                             (org-truss--section-at item))))
             (name (read-string "Label: " (and roles (org-truss-role-label (car roles))))))
        (org-truss--editing
          (org-truss-add-section (plist-get item :pos) name roles))))))

(defun org-truss--field-path (field)
  "Return FIELD as the start of a path, with its part: Subject › Issue."
  (format "%s › %s" (capitalize (symbol-name (org-truss-field-part field)))
          (org-truss-field-name field)))

(defun org-truss--path-segment (model member short)
  "Return MEMBER as one step of a path, cut short when SHORT.
A step says its number, and a part the aspect it covers or that it is a
part."
  (let* ((label (org-truss-member-label member))
         (label (if short (truncate-string-to-width label 20 nil nil "…") label))
         (up (org-truss-parent model member)))
    (if (not (and up (org-truss-how-child-p model member)))
        label
      (let ((aspect (org-truss-aspect-of up member)))
        (if (eq (org-truss-how-list up) 'numbered)
            (let ((n (seq-position (seq-remove #'org-truss-noexport-p (org-truss-how-children up))
                                   member)))
              (format "step%s: %s" (if n (format " %d" (1+ n)) "") label))
          (format "%s: %s" (if aspect (org-truss-role-name aspect) "part") label))))))

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
    (let ((field (org-truss-field-of model member)))
      (string-join (cons (if field (org-truss--field-path field) "Members") segments) " › "))))

(defun org-truss--member-choices (model)
  "Return (PATH . POSITION) for every member of MODEL, those not placed first."
  (let ((not-placed (plist-get (org-truss-checks model) :not-placed)))
    (mapcar (lambda (m) (cons (org-truss--member-path model m) (org-truss-member-pos m)))
            (append not-placed
                    (seq-remove (lambda (m) (memq m not-placed)) (org-truss-model-all model))))))

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
             (org-truss-replace-link section (plist-get item :link) ref)
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
  "Take away the sections below the section at point, keeping their links.
Its patterns go with them; see `org-truss-unwrap'."
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
  "Set the places the line at point fills in the patterns of the one above.
For a section, under the section above; for a field, under the brief or
the subject; for a member, under the member it is nested under, when that
one's patterns name places.  Those still empty are offered first, then the
rest those patterns name, then every role.  A heading can fill one place
for each pattern that asks: a major premise that is also told as a reason."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'section 'member 'brief))
         (pos (plist-get item :pos))
         (model (org-truss-read org-truss--source))
         (cluster (org-truss-cluster-at model pos))
         (parent (cond ((eq (plist-get item :type) 'section)
                        (org-truss--section-at item t))
                       ((org-truss-field-p cluster)
                        (seq-find (lambda (part) (and part (memq cluster (org-truss-part-children part))))
                                  (list (org-truss-model-brief model) (org-truss-model-subject model))))
                       ((org-truss-member-p cluster)
                        (org-truss-parent model cluster))
                       (t (user-error "Put point on a section, a field or a member")))))
    (when (and (org-truss-member-p cluster) (not (and parent (org-truss-asked-roles parent))))
      (user-error "A member takes a role only under one whose patterns name places"))
    (let ((roles (org-truss--read-roles "Fills: " (org-truss-cluster-roles cluster) parent)))
      (org-truss--editing (org-truss-set-roles pos roles)))))

(defun org-truss-board-flip ()
  "Tell the member at point after what is under it, or before.
A shortcut for the two telling patterns most often wanted, conclusion last
and conclusion first: a member told last is told first, and any other last.
The rest are on \\[org-truss-board-pattern]."
  (interactive)
  (let* ((item (org-truss--want (org-truss--item) 'member))
         (pos (plist-get item :pos))
         (member (org-truss-cluster-at (org-truss-read org-truss--source) pos)))
    (org-truss--editing
      (org-truss-set-pattern pos 'telling
                             (if (eq (org-truss-member-telling member) 'last) 'first 'last)))))

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
  (org-truss--edit (plist-get (org-truss--want (org-truss--item) 'section 'member 'broken 'brief 'use)
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
  (let* ((roles (org-truss-asked-roles parent))
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
  (when (plist-get (org-truss--item) :part)
    (user-error "Put point on a field of the %s to write a member under it"
                (plist-get (org-truss--item) :part)))
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
         (role (if (and next (org-truss-aspect-roles up))
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
                                       (org-truss-set-pattern head 'logic nil)
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
         (current (car (rassq (org-truss-member-kind model member) org-truss--kinds)))
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
                  (mapcar (lambda (field) (cons (org-truss-field-pos field) (org-truss--field-path field)))
                          (org-truss-fields model))
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
        (set-marker (org-truss-refile-member (plist-get item :pos) to) nil)
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
      ;; Its links are read from the truss file's directory, as they are
      ;; written there, so a picture it shows is found.
      (setq default-directory (org-truss--model-directory model))
      (when (display-images-p)
        (org-display-inline-images nil t))
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

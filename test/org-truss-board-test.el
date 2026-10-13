;;; org-truss-board-test.el --- Tests for org-truss-board  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -L test -l test/org-truss-board-test.el \
;;       -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss)
(require 'org-truss-core-test)

(defmacro org-truss-test--with-board (text &rest body)
  "Run BODY in a board drawn from an Org buffer holding TEXT.
`source' is bound to that buffer."
  (declare (indent 1))
  `(let ((source (generate-new-buffer " *truss source*"))
         (org-truss-language 'en))
     (unwind-protect
         (progn
           (with-current-buffer source
             (insert ,text)
             (org-mode))
           (with-temp-buffer
             (org-truss-board-mode)
             (setq org-truss--source source)
             (org-truss-board-redraw)
             ,@body))
       (kill-buffer source))))

(defun org-truss-test--goto-line-with (regexp)
  "Put point on the first board line matching REGEXP."
  (goto-char (point-min))
  (unless (re-search-forward regexp nil t)
    (error "No line matching %s" regexp))
  (beginning-of-line))

(defmacro org-truss-test--answering (answers &rest body)
  "Run BODY with every prompt answered, in turn, from ANSWERS."
  (declare (indent 1))
  `(let ((queue ,answers))
     (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (pop queue)))
               ((symbol-function 'completing-read-multiple) (lambda (&rest _) (pop queue)))
               ((symbol-function 'read-string) (lambda (&rest _) (pop queue)))
               ((symbol-function 'y-or-n-p) (lambda (&rest _) (pop queue))))
       ,@body)))

(defun org-truss-test--goto-told-line-with (regexp)
  "Put point on the first line of the board's structure matching REGEXP.
Members are drawn above it too, where they are worked on; in the structure
they are drawn as the document tells them."
  (org-truss-test--goto-line-with "^ Structure ")
  (unless (re-search-forward regexp nil t)
    (error "No line in the structure matching %s" regexp))
  (beginning-of-line))

(defun org-truss-test--column-of (regexp text &optional told)
  "Return the column TEXT starts at, after a gap, on the first line matching REGEXP.
In the structure when TOLD."
  (if told
      (org-truss-test--goto-told-line-with regexp)
    (org-truss-test--goto-line-with regexp))
  (re-search-forward (concat "[ ·][ ·]\\(" (regexp-quote text) "\\)") (line-end-position))
  (goto-char (match-beginning 1))
  (current-column))

(defun org-truss-test--structure-labels (source)
  (mapcar #'org-truss-section-label
          (org-truss-section-children (org-truss-model-structure (org-truss-read source)))))

(ert-deftest org-truss-test-board-draws ()
  "The board shows sections, members with their kind, gaps and what is undone."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "├ Sky[ ·]+Sky +Sky$" text))
      (should (string-match-p "^ Structure .*\n (tell › Sky, Rain, Umbrella)\n ├ Sky" text))
      (should (string-match-p
               "hypothesis[ ·]+Move to fortnightly +Hold the review every other week\\.\n +(why › deduction)$" text))
      (should (string-match-p "Minor premise —" text))
      (should (string-match-p "broken link[ ·]+\\[\\[#none\\]\\]" text))
      (should (string-match-p "^ Broken links\n +\\[\\[#none\\]\\] ← Umbrella$" text))
      (should (string-match-p "\n   Premises —\n" text))
      (should (string-match-p "^ Pattern gaps\n   Structure[ ·]+tell › Sky, Rain, Umbrella +Premises$" text))
      (should (string-match-p "^ Not placed$" text))
      (should (string-match-p "RET visit" text)))))

(ert-deftest org-truss-test-board-speaks-english ()
  "The board's own words stay English; the sections a pattern adds to the file
are named in `org-truss-language'."
  (org-truss-test--with-board org-truss-test--file
    (let ((org-truss-language 'ja))
      (org-truss-test--goto-line-with "^ Structure")
      (org-truss-test--answering '("tell › SCQA")
        (org-truss-board-pattern))
      (should (equal (org-truss-test--structure-labels source)
                     '("状況" "複雑化" "問い" "答え" "Sky" "Rain" "Umbrella")))
      (let ((text (buffer-string)))
        (should (string-match-p "^ Structure .*\n (tell › SCQA)$" text))
        (should (string-match-p "├ Complication[ ·]+複雑化 +複雑化$" text))
        (should (string-match-p "fact[ ·]+Reviews run long +Reviews ran past the hour eight times this quarter\\." text))))))

(ert-deftest org-truss-test-board-leaves-the-root-heading-out ()
  "The structure's own heading names the part, so the board calls it Structure."
  (org-truss-test--with-board (replace-regexp-in-string "^\\* Structure$" "* 構成"
                                                        org-truss-test--file)
    (should (string-match-p "^ Structure " (buffer-string)))
    (should-not (string-match-p "構成" (buffer-string)))
    (should (equal (caar (org-truss--section-choices (org-truss-read source)))
                   "Structure"))))

(ert-deftest org-truss-test-board-shows-the-fields ()
  "Under the title come the fields of the brief and the subject, each with its
text and the members written under it.  The reader, their question and the
issue are drawn even while empty; the rest once they hold something."
  (org-truss-test--with-board org-truss-test--conditions-file
    (should (string-match-p
             (concat "^ Reader[ ·]+The safety board\\.\n"
                     " Their question\n\n"
                     " Subject  .*\n"
                     " ├ Issue\n"
                     " │   bare[ ·]+Nobody checks before a test\n"
                     " └ Constraints[ ·]+Finance said so at the October meeting\\.\n"
                     "     fact[ ·]+No budget this year +→ Premises\n"
                     "     bare[ ·]+The schedule is fixed\n")
             (buffer-string)))
    (should-not (string-match-p "^ \\(Response wanted\\|Document constraints\\)"
                                (buffer-string)))
    (should-not (string-match-p "^ [├└] Premises$" (buffer-string)))
    (org-truss-test--goto-line-with "^ ├ Issue")
    (save-window-excursion
      (org-truss-board-visit)
      (should (equal (org-get-heading t t t t) "Issue")))
    (org-truss-test--goto-line-with "bare[ ·]+The schedule is fixed")
    (org-truss-test--answering '("Structure › Premises › Premises")
      (org-truss-board-place))
    ;; Placed, it is given an id to be pointed to by.
    (should (equal (org-truss-section-links
                    (car (org-truss-section-children
                          (org-truss-model-structure (org-truss-read source)))))
                   '("budget" "m1")))
    (should (equal (with-current-buffer source
                     (org-entry-get (org-truss-test--heading-pos "The schedule is fixed") "CUSTOM_ID"))
                   "m1"))))

(ert-deftest org-truss-test-board-cuts-long-headings ()
  "A heading too long for its room is cut short, so what the reader sees
keeps its column."
  (org-truss-test--with-board (replace-regexp-in-string
                               "Move to fortnightly"
                               "Move to fortnightly, starting next quarter, for every team"
                               org-truss-test--file t t)
    (should (string-match-p "Move to fortnightly, starting[^…\n]*…  Hold the review" (buffer-string)))
    (should (= (org-truss-test--column-of "hypothesis[ ·]+Move" "Hold the review every other week." t)
               (org-truss-test--column-of "fact[ ·]+Reviews run long" "Reviews ran past the hour" t)))
    (org-truss-test--goto-line-with "hypothesis[ ·]+Move")
    (re-search-forward "Move to")
    (should (equal (get-text-property (point) 'help-echo)
                   "Move to fortnightly, starting next quarter, for every team"))))

(ert-deftest org-truss-test-board-breaks-long-headings-with-entry-text ()
  "With entry text shown, a heading too long for its room is broken onto the
lines below instead of cut short."
  (let ((org-truss-language 'en)
        (text (replace-regexp-in-string
               "Move to fortnightly"
               "Move to fortnightly, starting next quarter, for every team"
               org-truss-test--file t t)))
    (org-truss-test--with text
      (let ((board (org-truss-board-text (org-truss-read) t)))
        (should-not (string-match-p "^ +hypothesis[ ·]+Move.*…  Hold.*\n +(why › deduction" board))
        (should (string-match-p (concat "hypothesis[ ·]+Move to fortnightly, starting next +"
                                        "Hold the review every other week\\.\n"
                                        " +quarter, for every team\n")
                                board))))))

(ert-deftest org-truss-test-board-fits-entry-text-to-the-window ()
  "Entry text breaks what the reader sees at the window's edge, or at a width
set for it; without entry text nothing is broken."
  (let ((org-truss-language 'en)
        (org-truss-board-right-width nil)
        (whole "Reviews ran past the hour eight times this quarter\\.$"))
    (org-truss-test--with org-truss-test--file
      (let ((model (org-truss-read)))
        (should-not (string-match-p whole (org-truss-board-text model t 120)))
        (should (string-match-p "Reviews ran past the hour eight times this\n.* quarter\\.$"
                                (org-truss-board-text model t 120)))
        (should (string-match-p whole (org-truss-board-text model t 200)))
        (let ((org-truss-board-right-width 20)
              (org-truss-board-middle-width 40))
          (should (equal (org-truss-board-text model t 120) (org-truss-board-text model t 300))))
        (let ((org-truss-board-middle-width 40))
          (should (equal (org-truss-board-text model nil 100) (org-truss-board-text model nil 300))))
        (should (string-match-p whole (org-truss-board-text model nil 100)))))))

(ert-deftest org-truss-test-board-fits-every-line-with-entry-text ()
  "With entry text shown, every line of the board fits the window: a field's
text, a ground, where a member is used, a title, whom to confirm with, a
labelled part and what a check lists are broken too, and nothing is cut."
  (let* ((org-truss-language 'en)
         (org-truss-board-middle-width nil)
         (org-truss-board-right-width nil)
         (long "long enough to run past any column of a board drawn this narrow")
         (text (replace-regexp-in-string "LONG" long "#+title: T
* Subject
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Constraints
:PROPERTIES:
:TRUSS_FIELD: constraints
:END:
The constraints, LONG.
- An item, LONG
*** A fact, LONG
:PROPERTIES:
:CUSTOM_ID: m1
:TRUSS_SOURCE: s
:END:
*** A question, LONG                                              :question:
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim, LONG
:PROPERTIES:
:CUSTOM_ID: m2
:TRUSS_GROUNDS: [[#m1]]
:TRUSS_LOGIC: 6w1h
:END:
*** Who does it, LONG
:PROPERTIES:
:TRUSS_ROLE: who
:TRUSS_CONFIRM: whoever is LONG
:END:
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
#+begin_public A title, LONG
#+end_public
- [[#m2]]
" t t)))
    (org-truss-test--with text
      (dolist (width '(100 160))
        (let ((board (org-truss-board-text (org-truss-read) t width)))
          (dolist (line (split-string board "\n"))
            (should (<= (string-width line) width)))
          (should-not (string-match-p "…" board)))))))

(ert-deftest org-truss-test-board-shares-the-window ()
  "Right of the board's own words, the file's words and what the reader sees
take half of the window each; a width set for the file's words fixes it."
  (let ((org-truss-language 'en)
        (org-truss-board-right-width nil))
    (org-truss-test--with org-truss-test--file
      (let* ((model (org-truss-read))
             (reader-column
              (lambda (width)
                (with-temp-buffer
                  (insert (org-truss-board-text model nil width))
                  (goto-char (point-min))
                  (re-search-forward "Reviews run long +")
                  (current-column))))
             (file-column
              (with-temp-buffer
                (insert (org-truss-board-text model nil 120))
                (goto-char (point-min))
                (re-search-forward "fact[ ·]+")
                (current-column))))
        (should (= (- (funcall reader-column 120) file-column)
                   (/ (+ (- 120 1 file-column) 2) 2)))
        (should (= (- (funcall reader-column 200) file-column)
                   (/ (+ (- 200 1 file-column) 2) 2)))
        (should (= (- (funcall reader-column 40) file-column) 20))
        (let ((org-truss-board-middle-width 40))
          (should (= (- (funcall reader-column 200) file-column) 40)))))))

(ert-deftest org-truss-test-board-views-the-document ()
  "v shows the document as x would write it, and the board keeps it current."
  (org-truss-test--with-board org-truss-test--file
    (save-window-excursion
      (org-truss-board-view)
      (should (equal (with-current-buffer org-truss--view (buffer-string))
                     (org-truss-render (org-truss-read source))))
      (with-current-buffer source
        (goto-char (org-truss-test--heading-pos "Sky"))
        (org-edit-headline "Where we are"))
      (org-truss-board-redraw)
      (should (string-match-p "^\\* Where we are$"
                              (with-current-buffer org-truss--view (buffer-string))))
      (kill-buffer org-truss--view))))

(ert-deftest org-truss-test-board-indents-by-the-parent ()
  "What a section or a member holds starts two columns right of its word:
the members a section lists, the grounds of a member.  The sections or
members under it branch off from the column of its word, as a tree, below
the line naming its pattern."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "^ ├ Sky[ ·]+Sky .*\n │   fact[ ·]+Reviews run long" text))
      (should (string-match-p "^ │   hypothesis[ ·]+Half the items repeat .*\n │   (why › reasons)\n │   ├ fact[ ·]+Agenda diff" text))
      (should (string-match-p "^ │   └ x objection[ ·]+Some items are urgent .*\n │     (why › reasons)\n │     ├ x fact[ ·]+Urgent items go to chat .*\n │     └ x question" text))
      (should (string-match-p "^   hypothesis[ ·]+Half the items repeat .*\n   (why › reasons)\n   │ ⬑ fact[ ·]+Reviews run long\n   ├ fact[ ·]+Agenda diff$" text))
      ;; The members' tree is drawn in a face of its own, the sections' not.
      (goto-char (point-min))
      (re-search-forward "^   \\(├\\) fact")
      (should (eq (get-text-property (match-beginning 1) 'face) 'org-truss-branch))
      (re-search-forward "^ \\(├\\) Rain")
      (should-not (get-text-property (match-beginning 1) 'face)))))

(ert-deftest org-truss-test-board-aligns-the-files-words ()
  "The file's words start in one column, however much the board says first."
  (org-truss-test--with-board org-truss-test--file
    (let ((columns (mapcar (lambda (spec) (org-truss-test--column-of (car spec) (cdr spec)))
                           '(("^ Title" . "Fortnightly reviews")
                             ("├ Sky" . "Sky")
                             ("hypothesis[ ·]+Move" . "Move to fortnightly")
                             ("x question" . "Who decides what is urgent")
                             ("^   bare" . "Lone remark")))))
      (should (= 1 (length (seq-uniq columns)))))))

(ert-deftest org-truss-test-board-help-follows-the-keys ()
  "The foot of the board names each key as it is bound where the board is."
  (org-truss-test--with-board org-truss-test--file
    (should (string-match-p " g redraw  " (buffer-string)))
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map org-truss-board-mode-map)
      (define-key map "g" #'ignore)
      (define-key map "G" #'org-truss-board-redraw)
      (use-local-map map)
      (org-truss-board-redraw)
      (should (string-match-p " G redraw  " (buffer-string))))))

(ert-deftest org-truss-test-board-shows-what-the-reader-sees ()
  "After the file's words comes what the reader sees: a title, or the start of
the body, with links read as their text."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "Rain[ ·]+Rain +Why it drags$" text))
      (should (string-match-p "Half the items repeat +Most items come back unchanged$" text))
      (should (string-match-p "fact[ ·]+Agenda diff +noexport$" text))
      (should (string-match-p "x fact[ ·]+Urgent items go to chat +Urgent items go to chat$" text))))
  (should (equal (substring-no-properties
                  (org-truss--reader-text '(nil . "As [[*Reviews run long]] shows,\nhalf repeat.\n\nMore.")))
                 "As Reviews run long shows, half repeat."))
  (should (equal (substring-no-properties (org-truss--reader-text '(nil . "| a | b |\n|---|\n| 1 | 2 |")))
                 "| a | b |"))
  (should (null (org-truss--reader-text '("" . "")))))

(ert-deftest org-truss-test-board-shows-entry-text ()
  "E puts what is under each heading below its line: the file's notes in the
file's column, the rest of what the reader sees on the right.  The line
naming its pattern stays right under it, the notes starting below when
the pattern's words run into their column."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-board-entry-text)
    (let ((column (org-truss-test--column-of "hypothesis[ ·]+Half the items repeat"
                                             "Half the items repeat" t)))
      (forward-line 1)
      (should (looking-at-p " │   (why › reasons) +Robin keeps raising the same items; +Half of each agenda"))
      (should (= column (progn (search-forward "Robin") (- (current-column) 5)))))
    (org-truss-board-entry-text)
    (should-not (string-match-p "Robin" (buffer-string)))))

(ert-deftest org-truss-test-board-wraps-a-line ()
  "w draws the line at point whole, as E draws every line, and leaves the
rest on one line; w again, from any of its lines, puts it back.  With entry
text shown, w puts a line on one line instead, and E draws every line one
way again."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-told-line-with "hypothesis[ ·]+Half the items repeat")
    (org-truss-board-wrap)
    (should (looking-at-p " │   hypothesis[ ·]+Half the items repeat"))
    (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 1))
    (should (string-match-p "Robin keeps raising[^├]*\n │   ├ fact[ ·]+Agenda diff" (buffer-string)))
    (forward-line 1)
    (org-truss-board-wrap)
    (should (looking-at-p " │   hypothesis[ ·]+Half the items repeat"))
    (should-not (string-match-p "Robin" (buffer-string)))
    (org-truss-board-entry-text)
    (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 2))
    (org-truss-test--goto-told-line-with "hypothesis[ ·]+Half the items repeat")
    (org-truss-board-wrap)
    (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 1))
    (org-truss-board-entry-text)
    (org-truss-board-entry-text)
    (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 2))))

(ert-deftest org-truss-test-board-keeps-the-pattern-under-its-member ()
  "With entry text, a pattern narrow enough for the board's own column goes
right under its member's line, beside the rest of its heading and notes; a
wider one waits for the heading to end.  The members' tree runs on down
past what is under a member."
  (let* ((org-truss-language 'en)
         (org-truss-board-middle-width 30)
         (long "long enough to break in a column this narrow")
         (text (replace-regexp-in-string "LONG" long "#+title: T
* Subject
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Constraints
:PROPERTIES:
:TRUSS_FIELD: constraints
:END:
*** A summary, LONG
:PROPERTIES:
:TRUSS_LOGIC: parts
:END:
**** A fact, LONG
:PROPERTIES:
:TRUSS_SOURCE: s
:END:
A note under it, LONG.
**** Another fact
:PROPERTIES:
:TRUSS_SOURCE: s
:END:
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim, LONG
:PROPERTIES:
:TRUSS_LOGIC: parts
:TRUSS_ASPECTS: 6w1h
:END:
A note under the claim.
*** Where it is done
:PROPERTIES:
:TRUSS_ROLE: where
:END:
" t t)))
    (org-truss-test--with text
      (let ((board (org-truss-board-text (org-truss-read) t 120)))
        (should (string-match-p
                 (concat "^     summary[ ·]+A summary, long enough to\n"
                         "     (how › parts)  break in a column this\n"
                         "     │ +narrow\n"
                         "     ├ fact[ ·]+A fact, long enough to break\n"
                         "     │ +in a column this narrow\n"
                         "     │ +A note under it, long enough\n"
                         "     │ +to break in a column this\n"
                         "     │ +narrow\\.\n"
                         "     └ fact[ ·]+Another fact\n")
                 board))
        (should (string-match-p
                 (concat "^   bare[ ·]+A claim, long enough to\n"
                         " +break in a column this\n"
                         " +narrow\n"
                         "   (how › parts, aspects › 6W1H)\n"
                         "   │ +A note under the claim\\.\n"
                         "   └ part  \\[Where\\]")
                 board))))))

(ert-deftest org-truss-test-board-runs-the-tree-down ()
  "The line of a tree starts right under a member's or a section's pattern,
or its line when it names none, and runs down past whatever comes before
what branches off: its notes, its grounds, the members a section lists,
and every line any of them is broken onto."
  (let* ((org-truss-language 'en)
         (org-truss-board-middle-width 30)
         (long "long enough to break in a column this narrow")
         (text (replace-regexp-in-string "LONG" long "#+title: T
* Subject
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Constraints
:PROPERTIES:
:TRUSS_FIELD: constraints
:END:
*** A fact, LONG
:PROPERTIES:
:CUSTOM_ID: m1
:TRUSS_SOURCE: s
:END:
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim
:PROPERTIES:
:CUSTOM_ID: m2
:TRUSS_GROUNDS: [[#m1]]
:END:
*** A reason
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[#m1]]
*** Later
- [[#m2]]
" t t)))
    (org-truss-test--with text
      (let ((model (org-truss-read)))
        (dolist (entries '(nil t))
          (let ((board (org-truss-board-text model entries 120)))
            (should (string-match-p
                     (concat "^   claim[ ·]+A claim.*\n"
                             "   (why › reasons)\n"
                             "   │ ⬑ fact[ ·]+A fact, long enough to.*\n"
                             (if entries "   │ +in a column this narrow\n" "")
                             "   └ ")
                     board))
            (should (string-match-p
                     (concat "^ └ no role[ ·]+Now.*\n"
                             "   │ fact[ ·]+A fact, long enough to.*\n"
                             (if entries "   │ +in a column this narrow\n" "")
                             "   └ no role[ ·]+Later")
                     board))))))))

(ert-deftest org-truss-test-board-colours-the-reader-s-text ()
  "On the right, what becomes a heading looks like one; what becomes body text
looks like the notes, with or without entry text."
  (org-truss-test--with-board org-truss-test--file
    (progn
      (dolist (entries '(nil t))
        (unless (eq org-truss--entry-text entries) (org-truss-board-entry-text))
        (goto-char (point-min))
        (should (eq (progn (search-forward "Most items come back unchanged")
                           (get-text-property (match-beginning 0) 'face))
                    'org-truss-reader))
        (goto-char (point-min))
        (should (eq (progn (search-forward "Reviews ran past the hour")
                           (get-text-property (match-beginning 0) 'face))
                    'org-truss-dim))
        (org-truss-test--goto-line-with "^ Structure ")
        (should (eq (progn (search-forward "Urgent items go to chat  ")
                           (skip-chars-forward " ")
                           (get-text-property (point) 'face))
                    'org-truss-dim)))
      (goto-char (point-min))
      (should (eq (progn (search-forward "Half of each agenda")
                         (get-text-property (match-beginning 0) 'face))
                  'org-truss-dim)))))

(ert-deftest org-truss-test-board-draws-pictures ()
  "With entry text, a picture linked on a line of its own is drawn in its
column, as wide as the column, on as many lines as it is high, each holding
a slice of it; the reader's column stays where it is beside it.  Where no
picture can be shown, and on one line, a link to a file is its name."
  (org-truss-test--in-directory '(("attach/ab/cdef/shot.png" . "png"))
    (let ((org-truss--base-directory dir)
          (text "Before.\n\n#+caption: The shot\n[[file:attach/ab/cdef/shot.png]]"))
      (should (equal (org-truss--fill text 30) '("Before." "" "#+caption: The shot" "shot.png")))
      (should (equal (org-truss--link-text "See [[file:sources/law.pdf]], [[./x.png][that]].")
                     "See law.pdf, that."))
      (cl-letf* ((asked nil)
                 ((symbol-function 'frame-char-height) (lambda (&rest _) 10))
                 ((symbol-function 'frame-char-width) (lambda (&rest _) 5))
                 ((symbol-function 'create-image)
                  (lambda (file &rest props) (setq asked props) (list 'image :file file)))
                 ((symbol-function 'image-size) (lambda (&rest _) '(150 . 25))))
        (let* ((org-truss--images t)
               (lines (org-truss--fill text 30))
               (slices (nthcdr 3 lines)))
          (should (equal (seq-take lines 3) '("Before." "" "#+caption: The shot")))
          (should (equal (plist-get (cddr asked) :max-width) 150))
          (should (equal (plist-get (cddr asked) :max-height)
                         (* 10 org-truss-board-image-height)))
          (should (eq (plist-get (cddr asked) :ascent) 'center))
          (should (equal (mapcar (lambda (line) (car (get-text-property 0 'display line))) slices)
                         '((slice 0 0 150 10) (slice 0 10 150 10) (slice 0 20 150 10))))
          (let* ((org-truss--middle-width 20)
                 (line (org-truss--lay-out (org-truss--line "" (car slices) "said") 10)))
            ;; Ten columns to the file's words, the slice, then the gap.
            (should (equal (get-text-property 11 'display line) '(space :align-to 30)))
            (should (string-suffix-p " said\n" line))
            (should (get-text-property (1- (length line)) 'line-height line)))))
      (should-not (org-truss--picture "[[file:attach/none.png]]"))
      (should-not (org-truss--picture "[[file:attach/ab/cdef/shot.png][The shot]]")))))

(ert-deftest org-truss-test-break ()
  "A line breaks within its width, not inside a word in narrow letters, and
not before closing punctuation."
  (should (equal (org-truss--break "one two three" 9) '("one two" "three")))
  (should (equal (org-truss--break "は 261 ms。" 9) '("は 261" "ms。")))
  (should (equal (org-truss--break "あいうえお。" 10) '("あいうえ" "お。"))))

(ert-deftest org-truss-test-one-line ()
  "A filled field reads as one line, with no space put between wide characters."
  (should (equal (org-truss--one-line "The team\nleads.") "The team leads."))
  (should (equal (org-truss--one-line "各自の\ndotfiles で書いている。\n次の行") "各自の dotfiles で書いている。次の行")))

(ert-deftest org-truss-test-board-applies-a-pattern ()
  "p on the root gives the structure a pattern's sections."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Structure")
    (org-truss-test--answering '("tell › SCQA")
      (org-truss-board-pattern))
    (should (equal (org-truss-test--structure-labels source)
                   '("Situation" "Complication" "Question" "Answer" "Sky" "Rain" "Umbrella")))
    (org-truss-test--goto-line-with "Rain ⚠[ ·]+Rain")
    (should (equal (get-text-property (point) 'help-echo)
                   "no place for Rain in SCQA"))))

(ert-deftest org-truss-test-board-marks-sections-outside-the-pattern ()
  "A section filling no place of its parent's pattern is marked."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
    (org-truss-test--answering '(("Answer"))
      (org-truss-board-roles))
    (org-truss-test--goto-line-with "└ Answer ⚠[ ·]+Umbrella")
    (should (string-prefix-p "no place for Answer in Sky, Rain, Umbrella. "
                             (get-text-property (point) 'help-echo)))))

(ert-deftest org-truss-test-board-marks-sections-named-by-the-pattern ()
  "A section the reader would meet under the pattern's name for its place is
marked; one with a title of its own is not."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (should (string-match-p "the pattern's name" (get-text-property (point) 'help-echo)))
    (search-forward "Sky" nil t 3)
    (should (eq (get-text-property (1- (point)) 'face) 'org-truss-attention))
    (org-truss-test--goto-line-with "├ Rain[ ·]+Rain")
    (should-not (get-text-property (point) 'help-echo))))

(ert-deftest org-truss-test-board-says ()
  "S on a listed member writes the words its section tells it in, and shows
them as what the reader sees; on a section it opens its lead to be written."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let ((default-directory dir)
          (org-truss-language 'en))
      (save-window-excursion
        (with-temp-buffer
          (org-truss-board))
        (with-current-buffer (get-buffer (format "*truss %s*" (abbreviate-file-name dir)))
          (org-truss-test--goto-told-line-with "fact[ ·]+Reviews run long")
          (org-truss-test--answering '("Our reviews overran.")
            (org-truss-board-say))
          (should (string-match-p "Reviews run long +Our reviews overran\\.$" (buffer-string)))
          (should (equal (with-current-buffer org-truss--source
                           (org-truss-link-wording (org-truss--part-pos "structure") "x"))
                         nil))
          (org-truss-test--goto-told-line-with "fact[ ·]+Reviews run long")
          (org-truss-test--answering '("Reviews run long")
            (org-truss-board-say))
          (should (string-match-p "Reviews run long +Reviews ran past the hour" (buffer-string)))
          (org-truss-board-save)
          (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
          (org-truss-board-say)
          (with-current-buffer "*truss edit*"
            (insert "Where we are.")
            (org-truss-edit-abort))
          ;; What the board does before each command.
          (org-truss-board-redraw)
          (should-not (string-match-p "begin_public\n\n" (with-current-buffer org-truss--source
                                                             (buffer-string))))
          (should-not (buffer-modified-p org-truss--source))
          (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
          (org-truss-board-say)
          (with-current-buffer "*truss edit*"
            (insert "Where we are.")
            (org-truss-edit-finish))
          (org-truss-board-redraw)
          (let ((org-truss--whole t))
            (should (equal (org-truss-section-public
                            (car (org-truss-section-children
                                  (org-truss-model-structure (org-truss-read org-truss--source)))))
                           '(nil . "Where we are."))))
          (org-truss-test--goto-line-with "├ Rain[ ·]+Rain")
          (org-truss-board-say)
          (with-current-buffer "*truss edit*"
            (org-truss-edit-finish))
          (should (string-match-p "#\\+begin_public Why it drags\n\n?#\\+end_public"
                                  (with-current-buffer org-truss--source (buffer-string)))))))))

(ert-deftest org-truss-test-board-applies-an-argument-pattern ()
  "p on a member gives it an argument pattern."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "hypothesis[ ·]+Half the items repeat")
    (org-truss-test--answering '("why › induction")
      (org-truss-board-pattern))
    (should (eq (org-truss-member-logic
                 (org-truss-member-by-label (org-truss-read source) "Half the items repeat"))
                'induction))))

(defun org-truss-test--top ()
  "Return the board above its structure: the title, the purpose and the fields."
  (let ((text (buffer-string)))
    (substring text 0 (string-match "^ Structure" text))))

(ert-deftest org-truss-test-board-folds ()
  "A field holding more members than the limit starts folded, saying how
many it holds; z unfolds it.  z among its members folds it again, and z on
a member folds what is nested under it.  c into a folded field unfolds it."
  (let ((org-truss-board-fold-limit 1))
    (org-truss-test--with-board org-truss-test--conditions-file
      (should (string-match-p "^ └ Constraints ▸2[ ·]+Finance said so" (buffer-string)))
      (should-not (string-match-p "^     fact[ ·]+No budget this year" (org-truss-test--top)))
      (org-truss-test--goto-line-with "^ └ Constraints")
      (org-truss-board-fold)
      (should (string-match-p "^     fact[ ·]+No budget this year" (org-truss-test--top)))
      (org-truss-test--goto-line-with "bare[ ·]+The schedule is fixed")
      (org-truss-board-fold)
      (should-not (string-match-p "^     bare[ ·]+The schedule is fixed" (org-truss-test--top)))
      (should (looking-at-p " └ Constraints ▸2"))
      (org-truss-test--creating '("Tests start at seven")
        (should (string-match-p "bare[ ·]+Tests start at seven" (buffer-string)))
        (should (equal (plist-get (org-truss--item) :label) "Tests start at seven")))))
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "hypothesis[ ·]+Half the items repeat")
    (org-truss-board-fold)
    (should (string-match-p "hypothesis ▸5[ ·]+Half the items repeat.*\n   hypothesis[ ·]+Move"
                            (buffer-string)))
    (org-truss-test--goto-line-with "hypothesis ▸5")
    (org-truss-board-fold)
    (should (string-match-p "hypothesis[ ·]+Half the items repeat.*\n   (why › reasons)\n   │ ⬑ fact[ ·]+Reviews run long"
                            (buffer-string)))
    (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
    (should-error (org-truss-board-fold) :type 'user-error)))

(ert-deftest org-truss-test-board-quotes ()
  "Q puts the text copied last under a member as its quotation, at the end of
its own text, and replaces it the next time, after asking."
  (org-truss-test--with-board org-truss-test--file
    (let ((own (lambda () (with-current-buffer source
                            (let ((b (org-truss--own-bounds (org-truss-test--heading-pos "Unused aside"))))
                              (buffer-substring-no-properties (car b) (cdr b)))))))
      (org-truss-test--goto-line-with "fact[ ·]+Unused aside")
      (let ((kill-ring (list "Said in the hallway.\n* not a heading")))
        (org-truss-test--answering '(t)
          (org-truss-board-quote)))
      (should (equal (funcall own)
                     (concat ":PROPERTIES:\n:CUSTOM_ID: aside\n:TRUSS_SOURCE: hallway\n:END:\n"
                             "#+begin_quote\nSaid in the hallway.\n * not a heading\n#+end_quote\n\n")))
      (org-truss-test--goto-line-with "fact[ ·]+Unused aside")
      (let ((kill-ring (list "Said twice.")))
        (org-truss-test--answering '(nil)
          (org-truss-board-quote))
        (should (string-match-p "Said in the hallway" (funcall own)))
        (org-truss-test--goto-line-with "fact[ ·]+Unused aside")
        (org-truss-test--answering '(t)
          (org-truss-board-quote)))
      (should (string-match-p "#\\+begin_quote\nSaid twice\\.\n#\\+end_quote\n\n\\'" (funcall own)))
      (should-not (string-match-p "hallway\\." (funcall own))))))

(ert-deftest org-truss-test-board-lists-unmet-constraints ()
  "A constraint of the subject the document does not use -- placed nowhere,
the ground of nothing placed -- is listed as unmet.  One a placed member
stands on is met; one only an unplaced member stands on is not."
  (org-truss-test--with-board org-truss-test--conditions-file
    (should (string-match-p "^ Unmet constraints\n   bare[ ·]+The schedule is fixed +The schedule is fixed$"
                            (buffer-string)))
    (org-truss-test--goto-line-with "bare[ ·]+Check with a breathalyser")
    (org-truss-test--answering '("Subject › Constraints › The schedule is fixed")
      (org-truss-board-ground))
    (should (string-match-p "^ Unmet constraints" (buffer-string)))
    (org-truss-test--goto-line-with "claim[ ·]+Check with a breathalyser")
    (org-truss-test--answering '("Structure › Premises › Premises")
      (org-truss-board-place))
    (should-not (string-match-p "^ Unmet constraints" (buffer-string)))))

(ert-deftest org-truss-test-board-visits-a-ground ()
  "RET on a ground goes to the member it names, not to the claim above it."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "⬑ fact[ ·]+Reviews run long")
    (save-window-excursion
      (org-truss-board-visit)
      (should (eq (current-buffer) source))
      (should (equal (org-get-heading t t t t) "Reviews run long")))))

(ert-deftest org-truss-test-board-colours-headings-by-level ()
  "A member's heading is drawn in the face Org gives a heading of its level,
whether or not the file has been fontified; nothing else of the file's
looks -- org-indent's prefixes, say -- comes onto the board."
  (org-truss-test--with-board org-truss-test--conditions-file
    (let ((face-of (lambda (regexp label)
                     (org-truss-test--goto-line-with regexp)
                     (search-forward label (line-end-position))
                     (get-text-property (match-beginning 0) 'face))))
      (should (eq (funcall face-of "bare[ ·]+Check with a breathalyser" "Check with")
                  'org-level-2))
      (should (eq (funcall face-of "fact[ ·]+No budget this year" "No budget") 'org-level-3))
      (with-current-buffer source
        (font-lock-ensure)
        (put-text-property (point-min) (point-max) 'line-prefix "  ")
        (should (equal-including-properties
                     (org-truss-member-label
                      (org-truss-member-by-label (org-truss-read) "No budget this year"))
                     "No budget this year")))
      (org-truss-board-redraw)
      (should (eq (funcall face-of "fact[ ·]+No budget this year" "No budget") 'org-level-3))
      (should-not (text-property-not-all (point-min) (point-max) 'line-prefix nil)))))

(ert-deftest org-truss-test-board-visit-opens-the-blocks ()
  "RET shows the entry it goes to with its blocks open, though they start
folded; the blocks of the headings under it stay as they were."
  (org-truss-test--with-board org-truss-test--file
    (let ((hidden (lambda (text)
                    (with-current-buffer source
                      (save-excursion
                        (goto-char (point-min))
                        (search-forward text)
                        (and (invisible-p (point)) t))))))
      (with-current-buffer source
        (org-fold-hide-block-all))
      (should (funcall hidden "Half of each agenda"))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Half the items repeat")
      (save-window-excursion
        (org-truss-board-visit))
      (should-not (funcall hidden "Half of each agenda"))
      (should (funcall hidden "We assume most items")))))

(ert-deftest org-truss-test-board-visits-the-brief ()
  "RET on the brief's lines goes to the brief, or to the field the line shows."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Reader")
    (save-window-excursion
      (org-truss-board-visit)
      (should (equal (org-get-heading t t t t) "Reader")))
    (org-truss-test--goto-line-with "^ Title")
    (save-window-excursion
      (org-truss-board-visit)
      (should (looking-at-p "#\\+title: Fortnightly reviews")))))

(ert-deftest org-truss-test-board-structure-takes-any-pattern ()
  "p on the Structure line offers every kind of pattern.  Aspects given to it
ask the sections right below to cover them, and a section is made for each
none covers yet; no telling takes the telling pattern off."
  (org-truss-test--with-board org-truss-test--file
    (let ((property (lambda (name)
                      (with-current-buffer source
                        (org-entry-get (org-truss-test--heading-pos "Structure") name)))))
      (org-truss-test--goto-line-with "^ Structure ")
      (org-truss-test--answering '("aspects › Past, present, future")
        (org-truss-board-pattern))
      (should (equal (funcall property "TRUSS_ASPECTS") "past-present-future"))
      (should (equal (funcall property "TRUSS_TELLING") "sky-rain-umbrella"))
      (should (equal (org-truss-test--structure-labels source)
                     '("Sky" "Rain" "Umbrella" "Past" "Present" "Future")))
      (should (string-match-p "^ (aspects › Past, present, future, tell › Sky, Rain, Umbrella)$"
                              (buffer-string)))
      (org-truss-test--goto-line-with "^ Structure ")
      (org-truss-test--answering '("no telling")
        (org-truss-board-pattern))
      (should-not (funcall property "TRUSS_TELLING"))
      (should (string-match-p "^ (aspects › Past, present, future)$" (buffer-string))))))

(ert-deftest org-truss-test-board-section-gaps ()
  "A section's patterns ask the sections right below it for their places.
s on a gap adds a section that fills it; r on a section offers the roles of
the patterns above, those still open first."
  (org-truss-test--with-board org-truss-test--file
    (with-current-buffer source
      (org-truss-set-pattern (org-truss-test--heading-pos "Umbrella") 'aspects '5w1h))
    (org-truss-board-redraw)
    (should (string-match-p "└ Umbrella[ ·]+Umbrella.*\n   (aspects › 5W1H)\n" (buffer-string)))
    (should (string-match-p "^     Who —$" (buffer-string)))
    (should (string-match-p "^   Umbrella[ ·]+Umbrella +Who, When, Where, What, Why, How$" (buffer-string)))
    (org-truss-test--goto-line-with "^     When —$")
    (org-truss-test--answering '("When we start")
      (org-truss-board-new-section))
    (with-current-buffer source
      (should (equal (org-entry-get (org-truss-test--heading-pos "When we start") "TRUSS_ROLE")
                     "when")))
    (should-not (string-match-p "^     When —$" (buffer-string)))
    (org-truss-test--goto-line-with "When we start")
    (let (offered)
      (cl-letf (((symbol-function 'completing-read-multiple)
                 (lambda (_prompt table &rest _) (setq offered table) '("Who"))))
        (org-truss-board-roles))
      (should (equal (seq-take offered 5) '("Who" "Where" "What" "Why" "How"))))
    (with-current-buffer source
      (should (equal (org-entry-get (org-truss-test--heading-pos "When we start") "TRUSS_ROLE")
                     "who")))
    (org-truss-test--goto-line-with "^     When —$")
    (should-error (org-truss-board-new) :type 'user-error)))

(defmacro org-truss-test--creating (answers &rest body)
  "Call `org-truss-board-new' with ANSWERS, then run BODY on the board.
The entry it opens is shown in `edit'."
  (declare (indent 1))
  `(let ((board (current-buffer)))
     (save-window-excursion
       (org-truss-test--answering ,answers
         (org-truss-board-new)))
     (set-buffer board)
     (let ((edit (get-buffer "*truss edit*")))
       ,@body)))

(defun org-truss-test--parent-label (source label)
  "Return the heading LABEL sits under in SOURCE, and its level, as (PARENT . LEVEL)."
  (with-current-buffer source
    (org-with-point-at (org-truss-test--heading-pos label)
      (let ((level (org-current-level)))
        (org-up-heading-safe)
        (cons (org-get-heading t t t t) level)))))

(ert-deftest org-truss-test-board-creates-a-member ()
  "c writes a new member and opens it to be written.  Away from any member,
field or section it goes at the top of the members, not placed; the board
goes to its line."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Title")
    (org-truss-test--creating '("Reviews start late")
      (should (equal (org-truss-test--parent-label source "Reviews start late")
                     '("Members" . 2)))
      (should (equal (plist-get (org-truss--item) :label) "Reviews start late"))
      (should (string-match-p "^ Not placed\n\\(.*\n\\)*   bare[ ·]+Reviews start late"
                              (buffer-string)))
      (with-current-buffer edit
        (should (equal (buffer-string) "** Reviews start late\n\n"))
        (should (= (point) (+ (point-min) (length "** Reviews start late\n"))))))
    (org-truss-test--goto-line-with "^ Title")
    (should-error (org-truss-test--answering '("Lone remark")
                    (org-truss-board-new))
                  :type 'user-error)))

(ert-deftest org-truss-test-board-creates-where-point-is ()
  "On a member c writes support for it, on a gap in the role the gap wants,
on a section a member listed there, and on a field a member under the field."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
    (org-truss-test--creating '("Eight of twelve ran over")
      (should (equal (org-truss-test--parent-label source "Eight of twelve ran over")
                     '("Reviews run long" . 3))))
    (org-truss-test--goto-line-with "Minor premise —")
    (org-truss-test--creating '("Our review repeats itself")
      (should (equal (org-truss-test--parent-label source "Our review repeats itself")
                     '("Move to fortnightly" . 3)))
      (should-not (string-match-p "Minor premise —" (buffer-string)))
      (with-current-buffer edit
        (should (looking-at-p "$"))
        (should (string-match-p ":TRUSS_ROLE: minor" (buffer-string)))))
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (org-truss-test--creating '("The team grew")
      (should (equal (org-truss-test--parent-label source "The team grew") '("Members" . 2)))
      (let ((model (org-truss-read source)))
        (should (equal (org-truss-member-id (org-truss-member-by-label model "The team grew")) "m1"))
        (should (member "m1"
                        (org-truss-section-links
                         (car (org-truss-section-children (org-truss-model-structure model)))))))))
  (org-truss-test--with-board org-truss-test--conditions-file
    (org-truss-test--goto-line-with "^ └ Constraints")
    (org-truss-test--creating '("Tests start at seven")
      (should (equal (org-truss-test--parent-label source "Tests start at seven")
                     '("Constraints" . 3))))))

(ert-deftest org-truss-test-board-starts-a-cluster ()
  "c under a member with nothing under it yet writes the logic pattern that
starts a cluster there -- why › reasons in the members, how › parts in the
subject -- and leaves one already written alone.  Taking the new member
back takes the pattern back too, and the file is as it was.  f does the
same for the member it moves under."
  (org-truss-test--with-board org-truss-test--file
    (let ((logic (lambda (label)
                   (with-current-buffer source
                     (org-entry-get (org-truss-test--heading-pos label) "TRUSS_LOGIC")))))
      (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
      (org-truss-test--creating '("Said twice")
        (should (equal (funcall logic "Lone remark") "reasons"))
        (should (string-match-p "claim[ ·]+Lone remark.*\n   (why › reasons)\n"
                                (buffer-string))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--creating '("Teams that tried it")
        (should (equal (funcall logic "Move to fortnightly") "deduction")))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Half the items repeat")
      (org-truss-test--creating '("Most agendas match")
        (should-not (funcall logic "Half the items repeat")))
      (org-truss-test--goto-line-with "fact[ ·]+Unused aside")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-refile))
      (should (equal (funcall logic "Lone remark") "reasons"))
      (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
      (org-truss-test--answering '("Members › Lone remark › Unused aside")
        (org-truss-board-refile))
      (should (equal (funcall logic "Unused aside") "reasons"))))
  (org-truss-test--with-board org-truss-test--conditions-file
    (org-truss-test--goto-line-with "fact[ ·]+No budget this year")
    (org-truss-test--creating '("The fund is spent")
      (should (equal (with-current-buffer source
                       (org-entry-get (org-truss-test--heading-pos "No budget this year") "TRUSS_LOGIC"))
                     "parts"))
      (should (string-match-p "fact[ ·]+No budget this year.*\n +(how › parts)\n" (buffer-string)))))
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let ((default-directory dir)
          (org-truss-language 'en))
      (save-window-excursion
        (with-temp-buffer
          (org-truss-board))
        (with-current-buffer (get-buffer (format "*truss %s*" (abbreviate-file-name dir)))
          (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
          (org-truss-test--answering '("Said twice")
            (org-truss-board-new))
          (with-current-buffer "*truss edit*"
            (org-truss-edit-abort))
          (with-current-buffer org-truss--source
            (should-not (org-entry-get (org-truss-test--heading-pos "Lone remark") "TRUSS_LOGIC"))
            (should-not (string-match-p "Said twice" (buffer-string))))
          (should-not (buffer-modified-p org-truss--source)))))))

(ert-deftest org-truss-test-board-says-what-a-member-is ()
  "t writes what makes a member the kind it is said to be, and takes off
what would make it another."
  (org-truss-test--with-board org-truss-test--file
    (let ((kind (lambda (label)
                  (let ((model (org-truss-read source)))
                    (org-truss-member-kind model (org-truss-member-by-label model label))))))
      (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
      (org-truss-test--answering '("assumption" "Robin")
        (org-truss-board-kind))
      (should (eq (funcall kind "Lone remark") 'assumption))
      (should (string-match-p "Lone remark +Lone remark  confirm with Robin" (buffer-string)))
      (org-truss-test--goto-line-with "assumption[ ·]+Lone remark")
      (org-truss-test--answering '("fact" "minutes, 2 October")
        (org-truss-board-kind))
      (should (eq (funcall kind "Lone remark") 'fact))
      (let ((member (org-truss-member-by-label (org-truss-read source) "Lone remark")))
        (should (equal (org-truss-member-source member) "minutes, 2 October"))
        (should-not (org-truss-member-confirm member))
        (should-not (org-truss-member-tags member)))
      (org-truss-test--goto-line-with "fact[ ·]+Lone remark")
      (org-truss-test--answering '("question")
        (org-truss-board-kind))
      (should (eq (funcall kind "Lone remark") 'question))
      (org-truss-test--goto-line-with "question[ ·]+Lone remark")
      (org-truss-test--answering '("claim")
        (org-truss-board-kind))
      (should (eq (funcall kind "Lone remark") 'bare))
      (should-not (org-truss-member-source
                   (org-truss-member-by-label (org-truss-read source) "Lone remark")))
      (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
      (should-error (org-truss-test--answering '("fact" "")
                      (org-truss-board-kind))
                    :type 'user-error))))

(ert-deftest org-truss-test-board-files-a-member ()
  "f moves a member, with what is nested under it, under a field, a member or
the top of the members.  Links still find it."
  (org-truss-test--with-board org-truss-test--conditions-file
    (org-truss-test--goto-line-with "fact[ ·]+No budget this year")
    (org-truss-test--answering '("Members")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "No budget this year") '("Members" . 2)))
    (should (equal (plist-get (org-truss--item) :label) "No budget this year"))
    (should-not (string-match-p "broken link" (buffer-string)))
    (org-truss-test--goto-line-with "bare[ ·]+Check with a breathalyser")
    (org-truss-test--answering '("Subject › Constraints")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "Check with a breathalyser")
                   '("Constraints" . 3))))
  (org-truss-test--with-board org-truss-test--file
    (let ((model (org-truss-read source)))
      (should-not (assoc "Members › Half the items repeat › Agenda diff"
                         (org-truss--file-choices
                          model (org-truss-member-by-label model "Half the items repeat")))))
    (org-truss-test--goto-line-with "hypothesis[ ·]+Half the items repeat")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "Half the items repeat")
                   '("Lone remark" . 3)))
    (should (equal (org-truss-test--parent-label source "Who decides what is urgent")
                   '("Some items are urgent" . 5)))))

(ert-deftest org-truss-test-board-numbers-steps ()
  "A step is drawn as one, numbered on the right as the reader will see it."
  (org-truss-test--with-board org-truss-test--steps-file
    (let ((text (buffer-string)))
      (should (string-match-p "claim[ ·]+Check before every test +Check before every test\n +(how › steps)" text))
      (should (string-match-p "step[ ·]+Meet the driver face to face +1\\. Meet the driver face to face$" text))
      (should (string-match-p "step[ ·]+Note the reading +noexport$" text))
      (should (string-match-p "step[ ·]+Breathe into the checker +2\\. The driver breathes" text))
      (should (string-match-p "x objection[ ·]+The checker may be broken +The checker may be broken$" text)))))

(ert-deftest org-truss-test-board-draws-parts ()
  "Parts are drawn as parts, with the bullet, or the aspect, the reader sees;
an aspect none covers is a gap, and c on one fills it."
  (org-truss-test--with-board org-truss-test--how-file
    (let ((text (buffer-string)))
      (should (string-match-p "claim\\|bare" text))
      (should (string-match-p "(how › parts, aspects › 5W1H)" text))
      (should (string-match-p "part  \\[Who\\][ ·]+The driver's manager +- Who: The driver's manager$" text))
      (should (string-match-p "step[ ·]+Meet the driver +1\\. Meet the driver$" text))
      (should (string-match-p "part[ ·]+A checker that works +- A checker that works$" text))
      (should (string-match-p "(why › reasons, tell › PREP)" text))
      (should (string-match-p "What —" text)))
    (org-truss-test--goto-line-with "What —")
    (org-truss-test--creating '("Breathe into the checker")
      (should (equal (org-truss-member-roles
                      (org-truss-member-by-label (org-truss-read source) "Breathe into the checker"))
                     '(what)))
      (should-not (string-match-p "What —" (buffer-string))))))

(ert-deftest org-truss-test-board-offers-members-by-path ()
  "Members are offered by where they are: from Members or their field,
through what they are nested under, cut short, to their own heading; a
step with its number, a part with its role.  A field comes just before
what is written under it."
  (org-truss-test--with org-truss-test--how-file
    (let ((model (org-truss-read)))
      (should (equal (org-truss--member-path
                      model (org-truss-member-by-label model "Read the checker"))
                     "Members › Check before every … › How: As follows › step 2: Read the checker"))
      (should (equal (org-truss--member-path
                      model (org-truss-member-by-label model "Someone to check"))
                     "Members › What a check needs › part: Someone to check"))))
  (org-truss-test--with org-truss-test--conditions-file
    (let* ((model (org-truss-read))
           (names (mapcar #'car (org-truss--file-choices
                                 model (org-truss-member-by-label model "Check with a breathalyser")))))
      (should (equal (seq-drop names (seq-position names "Subject › Constraints"))
                     '("Subject › Constraints"
                       "Subject › Constraints › No budget this year"
                       "Subject › Constraints › The schedule is fixed"
                       "Members"))))))

(ert-deftest org-truss-test-board-offers-patterns-by-family ()
  "p offers every logic pattern, the aspects where the logic takes them, and
the telling patterns, each kind beside the others; one written can be taken
off.  What a pattern asks for and is not there is put in, a heading for each
place.  o tells a member last, or as written."
  (org-truss-test--with org-truss-test--file
    (let* ((model (org-truss-read))
           (choices (lambda (cluster) (mapcar #'cdr (org-truss--pattern-choices cluster)))))
      (should (equal (funcall choices (org-truss-test--m model "Lone remark"))
                     '(reasons deduction induction steps parts
                       what-why-how pros-cons short-long past-present-future 5w1h 6w1h
                       first last prep sds scqa sky-rain-umbrella)))
      (should (equal (funcall choices (org-truss-test--m model "Move to fortnightly"))
                     '(reasons deduction induction steps parts
                       first last prep sds scqa sky-rain-umbrella (none . logic))))
      (should (equal (seq-drop (funcall choices (org-truss-model-structure model)) 11)
                     '(first last prep sds scqa sky-rain-umbrella (none . telling))))
      (should (equal (car (rassq 'prep (org-truss--pattern-choices
                                        (org-truss-test--m model "Lone remark"))))
                     "tell › PREP"))))
  (org-truss-test--with-board org-truss-test--file
    (let ((member (lambda () (org-truss-member-by-label (org-truss-read source) "Move to fortnightly"))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("tell › PREP")
        (org-truss-board-pattern))
      (should (eq (org-truss-member-logic (funcall member)) 'deduction))
      (should (eq (org-truss-member-telling (funcall member)) 'prep))
      (should (string-match-p "(why › deduction, tell › PREP)" (buffer-string)))
      (should (equal (mapcar (lambda (m) (cons (org-truss-member-label m) (org-truss-member-roles m)))
                             (org-truss-member-children (funcall member)))
                     '(("A meeting that repeats itself can meet less" major)
                       ("Reason" reason) ("Example" example))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-board-flip)
      (should (eq (org-truss-member-telling (funcall member)) 'last))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("no telling")
        (org-truss-board-pattern))
      (should-not (org-truss-member-telling (funcall member)))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("why › reasons")
        (org-truss-board-pattern))
      (should (eq (org-truss-member-logic (funcall member)) 'reasons))
      (should (string-match-p "(why › reasons)" (buffer-string))))))

(ert-deftest org-truss-test-board-creates-the-next-step ()
  "On a step c writes the next step, just after it; on a member that says how,
its last step; with a prefix argument, support under the step.  On a
labelled part it asks which role the next one fills."
  (org-truss-test--with-board org-truss-test--steps-file
    (let ((steps (lambda ()
                   (org-truss-test--labels
                    (org-truss-how-children
                     (org-truss-member-by-label (org-truss-read source) "Check before every test"))))))
      (org-truss-test--goto-line-with "step[ ·]+Meet the driver face to face")
      (org-truss-test--creating '("Show your face")
        (should (equal (funcall steps)
                       '("Meet the driver face to face" "Show your face"
                         "Note the reading" "Breathe into the checker")))
        (should (string-match-p "step[ ·]+Show your face +2\\. Show your face" (buffer-string))))
      (org-truss-test--goto-line-with "claim[ ·]+Check before every test")
      (org-truss-test--creating '("Thank the driver")
        (should (equal (car (last (funcall steps))) "Thank the driver")))
      (org-truss-test--goto-line-with "step[ ·]+Show your face")
      (let ((current-prefix-arg '(4)))
        (save-window-excursion
          (org-truss-test--answering '("The law asks to see it")
            (call-interactively #'org-truss-board-new))))
      (should (equal (org-truss-test--parent-label source "The law asks to see it")
                     '("Show your face" . 4)))))
  (org-truss-test--with-board org-truss-test--how-file
    (org-truss-test--goto-line-with "step[ ·]+Meet the driver")
    (org-truss-test--creating '("Show the reading")
      (should (equal (org-truss-test--parent-label source "Show the reading") '("As follows" . 4))))
    (org-truss-test--goto-line-with "part  \\[How\\][ ·]+As follows")
    (org-truss-test--creating '("Write it down")
      (should (equal (org-truss-test--parent-label source "Write it down") '("As follows" . 4))))
    (org-truss-test--goto-line-with "part  \\[Who\\][ ·]+The driver's manager")
    (org-truss-test--creating '("A breath test" "What")
      (should (equal (org-truss-test--parent-label source "A breath test")
                     '("Check before every test" . 3)))
      (should (equal (org-truss-member-roles
                      (org-truss-member-by-label (org-truss-read source) "A breath test"))
                     '(what))))))

(ert-deftest org-truss-test-board-edit-finishes-and-aborts ()
  "In an entry opened from the board, C-c C-c saves the file and closes it;
C-c C-k puts back what was there, takes away an entry written just now with
the link that placed it, and leaves the file unmodified when it was."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let ((default-directory dir)
          (org-truss-language 'en)
          (file (expand-file-name "truss.org" dir)))
      (save-window-excursion
        (with-temp-buffer
          (org-truss-board))
        (let ((board (get-buffer (format "*truss %s*" (abbreviate-file-name dir)))))
          (with-current-buffer board
            (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
            (org-truss-test--answering '("The team grew")
              (org-truss-board-new))
            (with-current-buffer "*truss edit*"
              (should org-truss-edit-mode)
              (should (string-match-p "C-c C-c" (format "%s" header-line-format)))
              (insert "Two joined in May.\n")
              (org-truss-edit-abort))
            (should-not (get-buffer "*truss edit*"))
            (should-not (string-match-p "The team grew" (with-current-buffer org-truss--source
                                                          (buffer-string))))
            (should-not (buffer-modified-p org-truss--source))
            (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
            (org-truss-board-edit)
            (with-current-buffer "*truss edit*"
              (goto-char (point-max))
              (insert "Said in passing.\n")
              (org-truss-edit-abort))
            (should-not (buffer-modified-p org-truss--source))
            (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
            (org-truss-board-edit)
            (with-current-buffer "*truss edit*"
              (goto-char (point-max))
              (insert "Said in passing.\n")
              (org-truss-edit-finish))
            (should-not (get-buffer "*truss edit*"))
            (should-not (buffer-modified-p org-truss--source))
            (should (string-match-p "\\*\\* Lone remark\n\nSaid in passing\\.\n"
                                    (with-temp-buffer
                                      (insert-file-contents file)
                                      (buffer-string))))))))))

(ert-deftest org-truss-test-init-sets-up-the-directory ()
  "init writes a truss file and puts beside it the directories its head
comment names and the file telling a coding agent where the rules are,
leaving what is there already.  A file written before gets the line that
keeps its attachments beside it, unsaved."
  (org-truss-test--in-directory
      '(("old/truss.org" . "#+title: Old\n* Members\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n")
        ("old/CLAUDE.md" . "Mine.\n"))
    (let ((org-truss-language 'en)
          (read (lambda (file)
                  (with-temp-buffer (insert-file-contents (expand-file-name file dir))
                                    (buffer-string)))))
      (save-window-excursion
        (org-truss-test--answering '("New")
          (org-truss-init (expand-file-name "new" dir)))
        (should (equal (buffer-file-name) (expand-file-name "new/truss.org" dir)))
        (should (string-prefix-p "# -*- org-attach-id-dir: \"attach/\"; -*-\n#+title: New\n"
                                 (buffer-string)))
        (should (equal org-attach-id-dir "attach/"))
        (dolist (sub '("new/sources" "new/notes"))
          (should (file-directory-p (expand-file-name sub dir))))
        (should (string-match-p "read the comment at the head of truss\\.org"
                                (funcall read "new/CLAUDE.md")))
        (org-truss-init (expand-file-name "old" dir))
        (should (string-prefix-p "# -*- org-attach-id-dir: \"attach/\"; -*-\n#+title: Old\n"
                                 (buffer-string)))
        (should (buffer-modified-p))
        (should (equal (funcall read "old/CLAUDE.md") "Mine.\n"))
        (should (file-directory-p (expand-file-name "old/sources" dir)))))))

(ert-deftest org-truss-test-board-asks-for-a-file ()
  "With no truss file near, the board asks for one: the file, its directory,
or anything below it.  Where there is none, it offers to start one."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file)
                                      (cons "notes/today.txt" "")
                                      (cons "elsewhere/x.txt" ""))
    (let ((truss (expand-file-name "truss.org" dir)))
      (dolist (answer (list truss dir (expand-file-name "notes/today.txt" dir)))
        (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) answer)))
          (should (equal (org-truss--ask-file) truss))))
      (cl-letf (((symbol-function 'read-file-name)
                 (lambda (&rest _) (expand-file-name "elsewhere/" dir)))
                ((symbol-function 'locate-dominating-file) (lambda (&rest _) nil))
                ((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (should-error (org-truss--ask-file) :type 'user-error)))))

(ert-deftest org-truss-test-board-outlives-its-file-buffer ()
  "The board visits its file again when the file's buffer is killed, and saves
it from the board."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let ((default-directory dir)
          (org-truss-language 'en))
      (save-window-excursion
        (with-temp-buffer
          (org-truss-board))
        (let ((board (get-buffer (format "*truss %s*" (abbreviate-file-name dir)))))
          (with-current-buffer board
            (should (equal default-directory dir))
            (kill-buffer org-truss--source)
            (org-truss--before-command)
            (should (buffer-live-p org-truss--source))
            (should (equal (buffer-file-name org-truss--source)
                           (expand-file-name "truss.org" dir)))
            (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
            (org-truss-test--answering '("question")
              (org-truss-board-kind))
            (should (string-match-p "^ Title  unsaved" (buffer-string)))
            (should (eq (command-remapping 'save-buffer) #'org-truss-board-save))
            (org-truss-board-save)
            (should-not (string-match-p "unsaved" (buffer-string)))
            (should (string-match-p "Lone remark +:question:"
                                    (with-temp-buffer
                                      (insert-file-contents (expand-file-name "truss.org" dir))
                                      (buffer-string))))))))))

(ert-deftest org-truss-test-board-shows-without-leaving ()
  "SPC shows the heading in another window and keeps the board selected."
  (org-truss-test--with-board org-truss-test--file
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (delete-other-windows)
      (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
      (let ((board (selected-window)))
        (org-truss-board-show)
        (should (eq (selected-window) board))
        (should (eq (window-buffer org-truss--show-window) source))
        (should (equal (with-selected-window org-truss--show-window
                         (org-get-heading t t t t))
                       "Reviews run long"))))))

(ert-deftest org-truss-test-board-renames-a-section ()
  "R rewrites a section's heading too."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (org-truss-test--answering '("How reviews run now")
      (org-truss-board-rename))
    (should (equal (car (org-truss-test--structure-labels source)) "How reviews run now"))
    (should (string-match-p "├ Sky[ ·]+How reviews run now" (buffer-string)))))

(ert-deftest org-truss-test-board-edits-one-entry ()
  "e opens the line's heading alone, sharing the file's text."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
    (save-window-excursion
      (org-truss-board-edit)
      (should (eq (buffer-base-buffer) source))
      (should (string-prefix-p "** Reviews run long" (buffer-string)))
      (should-not (string-match-p "Half the items" (buffer-string)))
      (goto-char (point-max))
      (insert "A note.\n")
      (should (with-current-buffer source
                (save-excursion (goto-char (point-min)) (search-forward "A note." nil t))))
      (kill-buffer))))

(ert-deftest org-truss-test-board-catches-up ()
  "Selected again after its file changed, the board draws again."
  (org-truss-test--with-board org-truss-test--file
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (with-current-buffer source
        (goto-char (org-truss-test--heading-pos "Sky"))
        (org-edit-headline "Where we are"))
      (org-truss--catch-up (selected-window))
      (should (string-match-p "├ Sky[ ·]+Where we are" (buffer-string))))))

(ert-deftest org-truss-test-board-moves-a-member ()
  "a on a placed member moves it to the chosen section: a member is placed
in one section at most."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
    (org-truss-test--answering '("Structure › Umbrella › Umbrella")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (null (org-truss-section-links (car (org-truss-section-children root)))))
      (should (equal (org-truss-section-links (nth 2 (org-truss-section-children root)))
                     '("move" "none" "long"))))))

(ert-deftest org-truss-test-board-places-an-unplaced-member ()
  "a on an unplaced member places it in the chosen section; on a section, a
member placed elsewhere is moved there, and one placed there stays put."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
    (org-truss-test--answering '("Structure › Sky › Sky")
      (org-truss-board-place))
    (should (equal (org-truss-section-links
                    (car (org-truss-section-children
                          (org-truss-model-structure (org-truss-read source)))))
                   '("long" "m1")))
    (should-not (string-match-p "^ Not placed\n.*\n   bare[ ·]+Lone remark" (buffer-string)))
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-section-links (car (org-truss-section-children root)))
                     '("long")))
      (should (equal (org-truss-section-links (nth 2 (org-truss-section-children root)))
                     '("move" "none" "m1"))))
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (should (equal (org-truss-section-links
                    (nth 2 (org-truss-section-children
                            (org-truss-model-structure (org-truss-read source)))))
                   '("move" "none" "m1")))))

(ert-deftest org-truss-test-board-places-instead-of-a-broken-link ()
  "a on a broken link places the chosen member where the link stands; one
placed elsewhere is moved from there."
  (org-truss-test--with-board org-truss-test--file
    (let ((links (lambda (n) (org-truss-section-links
                              (nth n (org-truss-section-children
                                      (org-truss-model-structure (org-truss-read source))))))))
      (org-truss-test--goto-line-with "broken link[ ·]+\\[\\[#none\\]\\]")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-place))
      (should (equal (funcall links 2) '("move" "m1")))
      (should-not (string-match-p "broken link" (buffer-string))))
    ;; A link that names a heading is broken too, and is put right the same way.
    (with-current-buffer source
      (goto-char (point-max))
      (insert "- [[*Reviews run long]]\n- [[#last]]\n"))
    (org-truss-board-redraw)
    (org-truss-test--goto-line-with "broken link[ ·]+\\[\\[\\*Reviews run long\\]\\]")
    (org-truss-test--answering '("Members › Reviews run long")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (null (org-truss-section-links (car (org-truss-section-children root)))))
      (should (equal (org-truss-section-links (nth 2 (org-truss-section-children root)))
                     '("move" "m1" "long" "last"))))))

(ert-deftest org-truss-test-board-takes-out-and-deletes ()
  "d takes a member out of the structure and leaves it in the file; D deletes
it from the file, with what is under it and what placed it, leaving the
grounds that named it to show as broken."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-told-line-with "fact[ ·]+Reviews run long")
    (org-truss-board-take-out)
    (let ((model (org-truss-read source)))
      (should (org-truss-member-by-label model "Reviews run long"))
      (should (null (org-truss-section-links
                     (car (org-truss-section-children (org-truss-model-structure model)))))))
    (org-truss-test--goto-line-with "hypothesis[ ·]+Half the items repeat")
    (org-truss-test--answering '(nil)
      (org-truss-board-delete))
    (should (org-truss-member-by-label (org-truss-read source) "Half the items repeat"))
    (org-truss-test--goto-line-with "hypothesis[ ·]+Half the items repeat")
    (org-truss-test--answering '(t)
      (org-truss-board-delete))
    (let ((model (org-truss-read source)))
      (should-not (org-truss-member-by-label model "Half the items repeat"))
      (should-not (org-truss-member-by-label model "Agenda diff"))
      (should (null (org-truss-section-links
                     (nth 1 (org-truss-section-children (org-truss-model-structure model))))))
      (should (equal (org-truss-member-grounds (org-truss-member-by-label model "Move to fortnightly"))
                     '("half"))))
    (should (string-match-p "⬑ broken ground[ ·]+\\[\\[#half\\]\\]" (buffer-string)))
    (should (string-match-p "^ Broken grounds\n +claim[ ·]+Move to fortnightly +\\[\\[#half\\]\\]$"
                            (buffer-string)))))

(ert-deftest org-truss-test-board-grounds ()
  "b makes another member a ground, or no longer one; on a ground's own line
it takes that ground away."
  (org-truss-test--with-board org-truss-test--file
    (let ((grounds (lambda () (org-truss-member-grounds
                               (org-truss-member-by-label (org-truss-read source) "Move to fortnightly")))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("Members › Unused aside")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("half" "aside")))
      (should (string-match-p "⬑ fact[ ·]+Unused aside" (buffer-string)))
      ;; A member pointed to for the first time is given an id.
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("half" "aside" "m1")))
      (should (with-current-buffer source
                (string-match-p ":TRUSS_GROUNDS: \\[\\[#half\\]\\] \\[\\[#aside\\]\\] \\[\\[#m1\\]\\]$"
                                (buffer-string))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-ground))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("Members › Half the items repeat")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("aside")))
      (org-truss-test--goto-line-with "⬑ fact[ ·]+Unused aside")
      (org-truss-board-ground)
      (should (null (funcall grounds)))
      (should-not (with-current-buffer source
                    (string-match-p "TRUSS_GROUNDS: *$" (buffer-string)))))))

(ert-deftest org-truss-test-board-unwrap-asks-before-losing ()
  "u asks before discarding a title, and does nothing when told no."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Structure")
    (org-truss-test--answering '(nil)
      (org-truss-board-unwrap))
    (should (= 3 (length (org-truss-test--structure-labels source))))
    (org-truss-test--answering '(t)
      (org-truss-board-unwrap))
    (should (null (org-truss-test--structure-labels source)))))

(ert-deftest org-truss-test-board-new-section-and-roles ()
  "s adds a section; r changes what it fills."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Structure")
    (org-truss-test--answering '(("Premises") "Premises")
      (org-truss-board-new-section))
    (should (equal (car (last (org-truss-test--structure-labels source))) "Premises"))
    (org-truss-test--goto-line-with "└ Premises")
    (org-truss-test--answering '(("Premises" "Rain"))
      (org-truss-board-roles))
    (should (equal (org-truss-section-roles
                    (car (last (org-truss-section-children
                                (org-truss-model-structure (org-truss-read source))))))
                   '(premises rain)))))

(ert-deftest org-truss-test-board-flips ()
  "o tells a member last, after what is under it, and again first, before it.
Told first asks nothing of what is under it, as no telling pattern does."
  (org-truss-test--with-board org-truss-test--file
    (let ((member (lambda () (org-truss-member-by-label (org-truss-read source) "Move to fortnightly"))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-board-flip)
      (should (eq (org-truss-member-telling (funcall member)) 'last))
      (should (string-match-p "(why › deduction, tell › conclusion last)" (buffer-string)))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-board-flip)
      (should (eq (org-truss-member-telling (funcall member)) 'first))
      (should (string-match-p "(why › deduction, tell › conclusion first)" (buffer-string)))
      (should (equal (org-truss-gaps (funcall member)) '((minor . 1)))))))

(ert-deftest org-truss-test-board-keeps-up-with-the-file ()
  "A hand edit to the file is drawn before the next command, which then acts
at once.  Fontifying the file is not an edit.  Only an edit made while a
command is asking makes it draw again instead of acting."
  (org-truss-test--with-board org-truss-test--file
    (let ((umbrella (lambda () (org-truss-section-links
                                (nth 2 (org-truss-section-children
                                        (org-truss-model-structure (org-truss-read source))))))))
      (with-current-buffer source
        (with-silent-modifications
          (put-text-property (point-min) (point-max) 'fontified t)))
      (should-not (org-truss--stale-p))
      (with-current-buffer source
        (goto-char (point-min))
        (insert "\n"))
      (should (org-truss--stale-p))
      (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
      (org-truss--before-command)
      (should-not (org-truss--stale-p))
      (org-truss-test--answering '("Structure › Umbrella › Umbrella")
        (org-truss-board-place))
      (should (member "long" (funcall umbrella)))
      (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _)
                   (with-current-buffer source
                     (goto-char (point-min))
                     (insert "\n"))
                   "Structure › Sky › Sky")))
        (should-error (org-truss-board-place) :type 'user-error))
      (should (member "long" (funcall umbrella))))))

(ert-deftest org-truss-test-board-orders-sections ()
  "M-down moves a section after its next sibling."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (org-truss-board-down)
    (should (equal (org-truss-test--structure-labels source) '("Rain" "Sky" "Umbrella")))))

(ert-deftest org-truss-test-board-draws-the-parts-in-order ()
  "The subject, the members and the structure each take a part of the board,
in the order the work is done, each followed by what is left to do there.
Outside the structure a line says where its member is used; in it, what
the document tells."
  (org-truss-test--with-board org-truss-test--clusters-file
    (let ((text (buffer-string)))
      (should (string-match-p
               (concat "^ Subject .*\n"
                       " ├ Premises\n"
                       " │   question[ ·]+How many cars we run\n"
                       " └ Constraints\n"
                       "     summary[ ·]+The manager checks every driver.* → Background\n"
                       "     (how › parts)\n"
                       "     ├ fact[ ·]+The rule asks for a check before driving\n")
               text))
      (should (string-match-p "fact[ ·]+A manager is named.* +ground of The law binds us, so we must check \\+1$" text))
      (should (string-match-p "^ Misplaced\n   claim[ ·]+The law binds us.* an interpretation" text))
      (should (string-match-p "^ Open questions\n   question[ ·]+How many cars we run" text))
      (should (< (string-match "^ Subject " text) (string-match "^ Members " text)
                 (string-match "^ Structure " text)))
      (should (string-match-p "^ Misplaced\n   fact[ ·]+The tester reads zero when sober +a fact" text))
      (should (string-match-p (concat "├ Situation[ ·]+Background +Background\n"
                                      " │   summary[ ·]+The manager checks.* +The rules ask for a check before and after driving\\.\n"
                                      " └ Conclusion")
                              text))
      (should (string-match-p "step[ ·]+The driver blows into the tester +1\\. The driver blows" text)))))

(ert-deftest org-truss-test-board-patterns-in-the-subject ()
  "A member of the subject is offered every logic pattern and the aspects,
and no telling pattern, since it is not told; c on the subject's own line
asks for a field, and on a fact of a cluster writes the next one."
  (org-truss-test--with org-truss-test--clusters-file
    (let ((model (org-truss-read)))
      (should (equal (mapcar #'cdr (org-truss--pattern-choices
                                    (org-truss-test--m model "The manager checks every driver before and after driving")))
                     '(reasons deduction induction steps parts
                       what-why-how pros-cons short-long past-present-future 5w1h 6w1h
                       (none . logic))))))
  (org-truss-test--with-board org-truss-test--clusters-file
    (org-truss-test--goto-line-with "^ Subject ")
    (should-error (org-truss-board-new) :type 'user-error)
    (org-truss-test--goto-line-with "fact[ ·]+The check may be made by video")
    (org-truss-test--creating '("The check may be made by phone")
      (should (equal (org-truss-test--parent-label source "The check may be made by phone")
                     '("The manager checks every driver before and after driving" . 4))))))

(ert-deftest org-truss-test-board-shows-what-is-unfinished ()
  "A section the file has too late is marked, saying which it is below; it
is listed with the placeholders and the empty sections under the
structure, a member placeholder under the members, its heading marked."
  (org-truss-test--with-board org-truss-test--unfinished-file
    (let ((text (buffer-string)))
      (should (string-match-p "^ ├ Sky ⚠[ ·]+空 " text))
      (should (equal (get-text-property (string-match "^ ├ Sky ⚠" text) 'help-echo text)
                     "Sky, Rain, Umbrella tells it before Rain, which is above it in the file"))
      (should (string-match-p "^ Out of order\n   Sky[ ·]+空 +below Rain$" text))
      (should (string-match-p "^ Placeholders\n   Rain[ ·]+Rain +Rain\n   Umbrella[ ·]+Umbrella +Umbrella$"
                              text))
      (should (string-match-p "^ Empty sections\n   Sky[ ·]+空 +Where we stand\n   no role[ ·]+Notes for later" text))
      (should (string-match-p "^ Placeholders\n   bare[ ·]+Reason +Reason\n   bare[ ·]+Example" text))
      (should (eq (get-text-property (string-match "Reason +Reason" text) 'face text)
                  'org-truss-attention)))))

(ert-deftest org-truss-test-board-tells-aspects-of-reasons ()
  "In the structure a reason covering an aspect shows it on the right, as
the reader is told it."
  (org-truss-test--with-board "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** We move
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_ASPECTS: pros-cons
:END:
*** Less time in meetings
:PROPERTIES:
:TRUSS_ROLE: pros
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
- [[#move]]
"
    (org-truss-test--goto-told-line-with "Less time in meetings")
    (should (string-match-p "Less time in meetings +Pros: Less time in meetings$"
                            (buffer-substring (point) (line-end-position))))))

(ert-deftest org-truss-test-board-tells-a-conclusion-last ()
  "In the structure, a member told after what is under it has its words on
a line below it, named for its place, as the document tells it; an arrow
runs down to them from its own line, beside what is under it.  An arrow
inside another keeps both."
  (let ((text "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** We move to fortnightly reviews
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_TELLING: scqa
:END:
#+begin_closing
So we hold the review every other week.
#+end_closing
*** Reviews are weekly
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
*** Half the items repeat
:PROPERTIES:
:TRUSS_ROLE: complication
:TRUSS_TELLING: last
:END:
**** The agenda diff shows it
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
- [[#move]]
"))
    (org-truss-test--with-board text
      (org-truss-test--goto-told-line-with "claim[ ·]+We move")
      (let ((told (buffer-substring (point) (point-max))))
        (should (string-match-p
                 (concat "We move to fortnightly reviews +┐\n"
                         ".*(why › reasons, tell › SCQA) +│\n"
                         ".*Reviews are weekly +│ Reviews are weekly\n"
                         ".*Half the items repeat +│ ┐\n"
                         ".*(why › reasons, tell › conclusion last) +│ │\n"
                         ".*The agenda diff shows it +│ │ The agenda diff shows it\n"
                         " +conclusion +│ └→ Half the items repeat\n"
                         " +answer +└→ So we hold the review every other week\\.\n")
                 told))))))

(provide 'org-truss-board-test)

;;; org-truss-board-test.el ends here

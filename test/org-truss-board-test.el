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
      (should (string-match-p "├ Situation[ ·]+Sky +Sky$" text))
      (should (string-match-p "^ Structure .*\n (how › proposal, tell › Sky, Rain, Umbrella)\n ├ Situation" text))
      (should (string-match-p
               "hypothesis[ ·]+Move to fortnightly +Hold the review every other week\\.\n +(why › deduction, conclusion last)$" text))
      (should (string-match-p "Minor premise —" text))
      (should (string-match-p "broken link[ ·]+No such member" text))
      (should (string-match-p "\n   Problem —\n   Cause —\n" text))
      (should (string-match-p "^ Pattern gaps\n   Structure[ ·]+how › proposal +Problem, Cause, Effect, Plan, Cost, Alternatives, Ask, Premises$" text))
      (should (string-match-p "^ Not placed$" text))
      (should (string-match-p "RET visit" text)))))

(ert-deftest org-truss-test-board-speaks-english ()
  "The board's own words stay English; the sections a pattern adds to the file
are named in `org-truss-language'."
  (org-truss-test--with-board org-truss-test--file
    (let ((org-truss-language 'ja))
      (org-truss-test--goto-line-with "^ Structure")
      (org-truss-test--answering '("tell › Problem solving")
        (org-truss-board-pattern))
      (should (equal (org-truss-test--structure-labels source)
                     '("Sky" "問題" "原因" "Umbrella" "進め方" "効果" "Rain")))
      (let ((text (buffer-string)))
        (should (string-match-p "^ Structure .*\n (how › proposal, tell › Problem solving)$" text))
        (should (string-match-p "├ Problem[ ·]+問題 +問題$" text))
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
    (should (equal (org-truss-section-links
                    (car (org-truss-section-children
                          (org-truss-model-structure (org-truss-read source)))))
                   '("No budget this year" "The schedule is fixed")))))

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
        (org-truss-board-reader-width nil)
        (whole "Reviews ran past the hour eight times this quarter\\.$"))
    (org-truss-test--with org-truss-test--file
      (let ((model (org-truss-read)))
        (should-not (string-match-p whole (org-truss-board-text model t 120)))
        (should (string-match-p "Reviews ran past the hour eight times this\n.* quarter\\.$"
                                (org-truss-board-text model t 120)))
        (should (string-match-p whole (org-truss-board-text model t 200)))
        (let ((org-truss-board-reader-width 20)
              (org-truss-board-heading-width 40))
          (should (equal (org-truss-board-text model t 120) (org-truss-board-text model t 300))))
        (let ((org-truss-board-heading-width 40))
          (should (equal (org-truss-board-text model nil 100) (org-truss-board-text model nil 300))))
        (should (string-match-p whole (org-truss-board-text model nil 100)))))))

(ert-deftest org-truss-test-board-shares-the-window ()
  "Right of the board's own words, the file's words and what the reader sees
take half of the window each; a width set for the file's words fixes it."
  (let ((org-truss-language 'en)
        (org-truss-board-reader-width nil))
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
        (let ((org-truss-board-heading-width 40))
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
  "What a section or a member holds starts two columns right of its word."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "^ ├ Situation[ ·]+Sky .*\n │   fact[ ·]+Reviews run long" text))
      (should (string-match-p "^ │   hypothesis[ ·]+Half the items repeat .*\n │     (why › reasons, conclusion first)\n │     fact[ ·]+Agenda diff" text))
      (should (string-match-p "^   hypothesis[ ·]+Half the items repeat .*\n     (why › reasons, conclusion first)\n     ⬑ fact[ ·]+Reviews run long$" text)))))

(ert-deftest org-truss-test-board-aligns-the-files-words ()
  "The file's words start in one column, however much the board says first."
  (org-truss-test--with-board org-truss-test--file
    (let ((columns (mapcar (lambda (spec) (org-truss-test--column-of (car spec) (cdr spec)))
                           '(("^ Title" . "Fortnightly reviews")
                             ("├ Situation" . "Sky")
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
      (should (string-match-p "Interpretation[ ·]+Rain +Why it drags$" text))
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
file's column, the rest of what the reader sees on the right."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-board-entry-text)
    (let ((column (org-truss-test--column-of "hypothesis[ ·]+Half the items repeat"
                                             "Half the items repeat" t)))
      (forward-line 1)
      (should (looking-at-p " │ +Robin keeps raising the same items; +Half of each agenda"))
      (should (= column (progn (search-forward "Robin") (- (current-column) 5)))))
    (org-truss-board-entry-text)
    (should-not (string-match-p "Robin" (buffer-string)))))

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
    (org-truss-test--answering '("tell › Problem solving")
      (org-truss-board-pattern))
    (should (equal (org-truss-test--structure-labels source)
                   '("Sky" "Problem" "Cause" "Umbrella" "Plan" "Effect" "Rain")))
    (org-truss-test--goto-line-with "Interpretation ⚠[ ·]+Rain")
    (should (equal (get-text-property (point) 'help-echo)
                   "no place for Interpretation in Problem solving"))))

(ert-deftest org-truss-test-board-marks-sections-outside-the-pattern ()
  "A section sharing no question with its parent's pattern is marked."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Conclusion[ ·]+Umbrella")
    (org-truss-test--answering '(("Ask"))
      (org-truss-board-roles))
    (org-truss-test--goto-line-with "└ Ask ⚠[ ·]+Umbrella")
    (should (string-prefix-p "no place for Ask in Sky, Rain, Umbrella. "
                             (get-text-property (point) 'help-echo)))))

(ert-deftest org-truss-test-board-marks-sections-named-by-the-pattern ()
  "A section the reader would meet under the pattern's name for its place is
marked; one with a title of its own is not."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "├ Situation[ ·]+Sky")
    (should (string-match-p "the pattern's name" (get-text-property (point) 'help-echo)))
    (search-forward "Sky" nil t 2)
    (should (eq (get-text-property (1- (point)) 'face) 'org-truss-attention))
    (org-truss-test--goto-line-with "├ Interpretation[ ·]+Rain")
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
          (org-truss-test--goto-line-with "├ Situation[ ·]+Sky")
          (org-truss-board-say)
          (with-current-buffer "*truss edit*"
            (insert "Where we are.")
            (org-truss-edit-abort))
          ;; What the board does before each command.
          (org-truss-board-redraw)
          (should-not (string-match-p "begin_public\n\n" (with-current-buffer org-truss--source
                                                             (buffer-string))))
          (should-not (buffer-modified-p org-truss--source))
          (org-truss-test--goto-line-with "├ Situation[ ·]+Sky")
          (org-truss-board-say)
          (with-current-buffer "*truss edit*"
            (insert "Where we are.")
            (org-truss-edit-finish))
          (org-truss-board-redraw)
          (let ((org-truss--entries t))
            (should (equal (org-truss-section-public
                            (car (org-truss-section-children
                                  (org-truss-model-structure (org-truss-read org-truss--source)))))
                           '(nil . "Where we are."))))
          (org-truss-test--goto-line-with "├ Interpretation[ ·]+Rain")
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
    (should (string-match-p "hypothesis[ ·]+Half the items repeat.*\n     (why › reasons, conclusion first)\n     ⬑ fact[ ·]+Reviews run long"
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
                     (concat ":PROPERTIES:\n:TRUSS_SOURCE: hallway\n:END:\n"
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

(ert-deftest org-truss-test-board-structure-takes-a-logic-pattern ()
  "p on the Structure line offers logic patterns beside the telling ones: the
purpose of the document is the structure's logic, and what it asks for is
listed as its gaps.  No logic asks for nothing but premises."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Structure ")
    (org-truss-test--answering '("how › report")
      (org-truss-board-pattern))
    (should (equal (with-current-buffer source
                     (org-entry-get (org-truss-test--heading-pos "Structure") "TRUSS_LOGIC"))
                   "report"))
    (should (equal (with-current-buffer source
                     (org-entry-get (org-truss-test--heading-pos "Structure") "TRUSS_TELLING"))
                   "sky-rain-umbrella"))
    (should (string-match-p "^ (how › report, tell › Sky, Rain, Umbrella)$" (buffer-string)))
    (should (string-match-p "^ Pattern gaps\n   Structure.* Problem, Cause, Plan, Premises$" (buffer-string)))
    (org-truss-test--goto-line-with "^ Structure ")
    (org-truss-test--answering '("no logic")
      (org-truss-board-pattern))
    (should-not (with-current-buffer source
                  (org-entry-get (org-truss-test--heading-pos "Structure") "TRUSS_LOGIC")))
    (should (string-match-p "^   Structure.* Premises$" (buffer-string)))))

(ert-deftest org-truss-test-board-section-gaps ()
  "A section takes a logic pattern too, and asks the sections right below it
for its roles.  s on a gap adds a section that answers it; r on a section
offers the roles of the pattern above, those still open first."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Conclusion[ ·]+Umbrella")
    (org-truss-test--answering '("how › 5W1H")
      (org-truss-board-pattern))
    (should (string-match-p "└ Conclusion[ ·]+Umbrella.*\n   (how › 5W1H)\n" (buffer-string)))
    (should (string-match-p "^     Who —$" (buffer-string)))
    (should (string-match-p "^   Conclusion[ ·]+Umbrella +Who, When, Where, What, Why, How$" (buffer-string)))
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
    (org-truss-test--goto-line-with "├ Situation[ ·]+Sky")
    (org-truss-test--creating '("The team grew")
      (should (equal (org-truss-test--parent-label source "The team grew") '("Members" . 2)))
      (should (member "The team grew"
                      (org-truss-section-links
                       (car (org-truss-section-children
                             (org-truss-model-structure (org-truss-read source)))))))))
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
        (should (string-match-p "claim[ ·]+Lone remark.*\n     (why › reasons, conclusion first)\n"
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
                    (org-truss-kind model (org-truss-member-by-label model label))))))
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
      (should (string-match-p "claim[ ·]+Check before every test +Check before every test\n +(how › steps, conclusion first)" text))
      (should (string-match-p "step[ ·]+Meet the driver face to face +1\\. Meet the driver face to face$" text))
      (should (string-match-p "step[ ·]+Note the reading +noexport$" text))
      (should (string-match-p "step[ ·]+Breathe into the checker +2\\. The driver breathes" text))
      (should (string-match-p "x objection[ ·]+The checker may be broken +The checker may be broken$" text)))))

(ert-deftest org-truss-test-board-draws-parts ()
  "Parts are drawn as parts, with the bullet or the label the reader sees;
a labelled part's missing roles are gaps, and c on one fills it."
  (org-truss-test--with-board org-truss-test--how-file
    (let ((text (buffer-string)))
      (should (string-match-p "claim\\|bare" text))
      (should (string-match-p "(how › 5W1H, conclusion first)" text))
      (should (string-match-p "part  \\[Who\\][ ·]+The driver's manager +- Who: The driver's manager$" text))
      (should (string-match-p "step[ ·]+Meet the driver +1\\. Meet the driver$" text))
      (should (string-match-p "part[ ·]+A checker that works +- A checker that works$" text))
      (should (string-match-p "(why › reasons, PREP)" text))
      (should (string-match-p "What —" text)))
    (org-truss-test--goto-line-with "What —")
    (org-truss-test--creating '("Breathe into the checker")
      (should (eq (org-truss-member-role
                   (org-truss-member-by-label (org-truss-read source) "Breathe into the checker"))
                  'what))
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
  "p offers a member's patterns by where they stand, and a telling pattern
is set beside the logic pattern, not in its place."
  (should (equal (mapcar #'car (org-truss--pattern-choices nil))
                 '("why › reasons" "why › induction" "why › deduction"
                   "how › steps" "how › parts" "how › 6W1H" "how › 5W1H"
                   "how › proposal" "how › report" "how › explanation"
                   "tell › conclusion first" "tell › conclusion last" "tell › PREP")))
  (should (equal (mapcar #'cdr (org-truss--pattern-choices t))
                 '(reasons induction deduction steps parts 6w1h 5w1h proposal report explanation
                   sky-rain-umbrella scqa problem-solving :none)))
  (org-truss-test--with-board org-truss-test--file
    (let ((member (lambda () (org-truss-member-by-label (org-truss-read source) "Move to fortnightly"))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("tell › PREP")
        (org-truss-board-pattern))
      (should (eq (org-truss-member-logic (funcall member)) 'deduction))
      (should (eq (org-truss-member-telling (funcall member)) 'prep))
      (should (string-match-p "(why › deduction, PREP)" (buffer-string)))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-board-flip)
      (should (eq (org-truss-member-telling (funcall member)) 'last))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("why › reasons")
        (org-truss-board-pattern))
      (should (eq (org-truss-member-logic (funcall member)) 'reasons))
      (should (string-match-p "(why › reasons, conclusion last)" (buffer-string))))))

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
      (should (eq (org-truss-member-role
                   (org-truss-member-by-label (org-truss-read source) "A breath test"))
                  'what)))))

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
            (org-truss-test--goto-line-with "├ Situation[ ·]+Sky")
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

(defmacro org-truss-test--in-directory (files &rest body)
  "Run BODY in a new directory `dir' holding FILES, (NAME . TEXT) pairs."
  (declare (indent 1))
  `(let ((dir (file-name-as-directory (make-temp-file "org-truss-test" t))))
     (unwind-protect
         (progn
           (dolist (file ,files)
             (make-directory (file-name-directory (expand-file-name (car file) dir)) t)
             (with-temp-file (expand-file-name (car file) dir)
               (insert (cdr file))))
           ,@body)
       (dolist (buffer (buffer-list))
         (when (or (string-prefix-p dir (or (buffer-file-name buffer) ""))
                   (string-prefix-p "*truss " (buffer-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory dir t))))

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
    (org-truss-test--goto-line-with "├ Situation[ ·]+Sky")
    (org-truss-test--answering '("How reviews run now")
      (org-truss-board-rename))
    (should (equal (car (org-truss-test--structure-labels source)) "How reviews run now"))
    (should (string-match-p "├ Situation[ ·]+How reviews run now" (buffer-string)))))

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
      (should (string-match-p "├ Situation[ ·]+Where we are" (buffer-string))))))

(ert-deftest org-truss-test-board-moves-a-member ()
  "a on a placed member moves it to the chosen section: a member is placed
in one section at most."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
    (org-truss-test--answering '("Structure › Conclusion › Umbrella")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (null (org-truss-section-links (car (org-truss-section-children root)))))
      (should (equal (org-truss-section-links (nth 2 (org-truss-section-children root)))
                     '("Move to fortnightly" "No such member" "Reviews run long"))))))

(ert-deftest org-truss-test-board-places-an-unplaced-member ()
  "a on an unplaced member places it in the chosen section; on a section, a
member placed elsewhere is moved there, and one placed there stays put."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "bare[ ·]+Lone remark")
    (org-truss-test--answering '("Structure › Situation › Sky")
      (org-truss-board-place))
    (should (equal (org-truss-section-links
                    (car (org-truss-section-children
                          (org-truss-model-structure (org-truss-read source)))))
                   '("Reviews run long" "Lone remark")))
    (should-not (string-match-p "^ Not placed\n.*\n   bare[ ·]+Lone remark" (buffer-string)))
    (org-truss-test--goto-line-with "└ Conclusion[ ·]+Umbrella")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-section-links (car (org-truss-section-children root)))
                     '("Reviews run long")))
      (should (equal (org-truss-section-links (nth 2 (org-truss-section-children root)))
                     '("Move to fortnightly" "No such member" "Lone remark"))))
    (org-truss-test--goto-line-with "└ Conclusion[ ·]+Umbrella")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (should (equal (org-truss-section-links
                    (nth 2 (org-truss-section-children
                            (org-truss-model-structure (org-truss-read source)))))
                   '("Move to fortnightly" "No such member" "Lone remark")))))

(ert-deftest org-truss-test-board-places-instead-of-a-broken-link ()
  "a on a broken link places the chosen member where the link stands; one
placed elsewhere is moved from there."
  (org-truss-test--with-board org-truss-test--file
    (let ((links (lambda (n) (org-truss-section-links
                              (nth n (org-truss-section-children
                                      (org-truss-model-structure (org-truss-read source))))))))
      (org-truss-test--goto-line-with "broken link[ ·]+No such member")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-place))
      (should (equal (funcall links 2) '("Move to fortnightly" "Lone remark")))
      (should-not (string-match-p "broken link" (buffer-string))))
    (with-current-buffer source
      (goto-char (point-max))
      (insert "- [[*Gone too]]\n- [[*Last]]\n"))
    (org-truss-board-redraw)
    (org-truss-test--goto-line-with "broken link[ ·]+Gone too")
    (org-truss-test--answering '("Members › Reviews run long")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (null (org-truss-section-links (car (org-truss-section-children root)))))
      (should (equal (org-truss-section-links (nth 2 (org-truss-section-children root)))
                     '("Move to fortnightly" "Lone remark" "Reviews run long" "Last"))))))

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
                     '("Half the items repeat"))))
    (should (string-match-p "⬑ broken link[ ·]+Half the items repeat" (buffer-string)))))

(ert-deftest org-truss-test-board-grounds ()
  "b makes another member a ground, or no longer one; on a ground's own line
it takes that ground away."
  (org-truss-test--with-board org-truss-test--file
    (let ((grounds (lambda () (org-truss-member-grounds
                               (org-truss-member-by-label (org-truss-read source) "Move to fortnightly")))))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("Members › Unused aside")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("Half the items repeat" "Unused aside")))
      (should (string-match-p "⬑ fact[ ·]+Unused aside" (buffer-string)))
      (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
      (org-truss-test--answering '("Members › Half the items repeat")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("Unused aside")))
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
  "s adds a section; r changes what it answers."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Structure")
    (org-truss-test--answering '(("Ask") "Ask")
      (org-truss-board-new-section))
    (should (equal (car (last (org-truss-test--structure-labels source))) "Ask"))
    (org-truss-test--goto-line-with "└ Ask")
    (org-truss-test--answering '(("Ask" "Plan"))
      (org-truss-board-roles))
    (should (equal (org-truss-section-roles
                    (car (last (org-truss-section-children
                                (org-truss-model-structure (org-truss-read source))))))
                   '(ask plan)))))

(ert-deftest org-truss-test-board-flips ()
  "o flips where an argument's conclusion goes."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "hypothesis[ ·]+Move to fortnightly")
    (org-truss-board-flip)
    (should (eq (org-truss-conclusion-position
                 (org-truss-member-by-label (org-truss-read source) "Move to fortnightly"))
                'first))))

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
      (org-truss-test--answering '("Structure › Conclusion › Umbrella")
        (org-truss-board-place))
      (should (member "Reviews run long" (funcall umbrella)))
      (org-truss-test--goto-line-with "fact[ ·]+Reviews run long")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _)
                   (with-current-buffer source
                     (goto-char (point-min))
                     (insert "\n"))
                   "Structure › Situation › Sky")))
        (should-error (org-truss-board-place) :type 'user-error))
      (should (member "Reviews run long" (funcall umbrella))))))

(ert-deftest org-truss-test-board-orders-sections ()
  "M-down moves a section after its next sibling."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "├ Situation[ ·]+Sky")
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
                       "       (how › parts)\n"
                       "       fact[ ·]+The rule asks for a check before driving\n")
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
  "A member of the subject is offered every logic pattern, and no telling
pattern, since it is not told; c on the subject's own line asks for a
field, and on a fact of a cluster writes the next one."
  (should (equal (mapcar #'cdr (org-truss--pattern-choices nil t))
                 '(reasons induction deduction steps parts 6w1h 5w1h proposal report explanation)))
  (org-truss-test--with-board org-truss-test--clusters-file
    (org-truss-test--goto-line-with "^ Subject ")
    (should-error (org-truss-board-new) :type 'user-error)
    (org-truss-test--goto-line-with "fact[ ·]+The check may be made by video")
    (org-truss-test--creating '("The check may be made by phone")
      (should (equal (org-truss-test--parent-label source "The check may be made by phone")
                     '("The manager checks every driver before and after driving" . 4))))))

(provide 'org-truss-board-test)

;;; org-truss-board-test.el ends here

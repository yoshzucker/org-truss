;;; org-truss-board-test.el --- Tests for org-truss-board  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -L test -l test/org-truss-board-test.el \
;;       -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss)
(require 'org-truss-core-test)

;; The board starts folded, as an Org file starts in overview; these tests
;; read what it draws, so they draw it open, and fold it where they mean
;; to.  `org-truss-test-board-starts-folded' draws it as it starts.
(setq org-truss-board-fold-limit nil)

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
       (org-truss-test--close-copies)
       (kill-buffer source))))

;; Headings the board takes out to be written in go into org-dock's copies;
;; in a directory of the tests' own, not the user's.
(setq org-dock-directory (file-name-as-directory (make-temp-file "org-truss-dock" t)))

(defun org-truss-test--copy ()
  "Return the buffer of the heading taken out to be written in, or nil."
  (seq-find (lambda (buffer) (buffer-local-value 'org-dock--session buffer))
            (buffer-list)))

(defun org-truss-test--close-copies ()
  "Close every copy of a heading taken out, as if let go unasked."
  (dolist (buffer (buffer-list))
    (when (buffer-local-value 'org-dock--session buffer)
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer))))

(defun org-truss-test--let-go ()
  "Let the copy in this buffer go, saying yes to letting its changes go."
  (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
    (org-dock-abort)))

(defun org-truss-test--goto-line-with (regexp &optional from)
  "Put point on the first board line matching REGEXP, after FROM if given.
Not on a line marked ▤ or ↥, where a member is used, which names it as its
own line does, unless REGEXP asks for the mark."
  (goto-char (or from (point-min)))
  (let ((found nil))
    (while (and (not found) (re-search-forward regexp nil t))
      (setq found (or (string-match-p "[▤↥]" regexp)
                      (not (eq (plist-get (get-text-property (line-beginning-position) 'org-truss-item)
                                          :type)
                               'use)))))
    (unless found
      (error "No line matching %s" regexp)))
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

(defun org-truss-test--told ()
  "Draw the board with the members a section lists opened where told."
  (unless (eq org-truss--board-order 'told)
    (setq org-truss--board-order 'told)
    (org-truss-board-redraw)))

(defun org-truss-test--goto-told-line-with (regexp)
  "Put point on the first line of the board's structure matching REGEXP.
Members are drawn above it too, where they are worked on; in the structure
they are drawn as the document tells them, opened there once the board
opens them where they are told, as this does."
  (org-truss-test--told)
  (org-truss-test--goto-line-with "^ Structure ")
  (org-truss-test--goto-line-with regexp (point)))

(defun org-truss-test--column-of (regexp text &optional told)
  "Return the column TEXT starts at, after a gap, on the first line matching REGEXP.
In the structure when TOLD."
  (if told
      (org-truss-test--goto-told-line-with regexp)
    (org-truss-test--goto-line-with regexp))
  (re-search-forward (concat "[ ·][ ·]\\(?:\\[*#[^] ]+]* \\)?\\(" (regexp-quote text) "\\)")
                     (line-end-position))
  (goto-char (match-beginning 1))
  (current-column))

(defun org-truss-test--structure-labels (source)
  (mapcar #'org-truss-section-label
          (org-truss-section-children (org-truss-model-structure (org-truss-read source)))))

(ert-deftest org-truss-test-board-draws ()
  "The board shows sections, members by the roles they play, missing roles
and what is undone."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky +Sky$" text))
      (should (string-match-p "^ Structure .*\n (telling › Sky, Rain, Umbrella)\n ├ Sky" text))
      (should (string-match-p
               "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly +Move to fortnightly\n +(logic › deduction)$" text))
      (should (string-match-p "Minor premise —" text))
      (should (string-match-p "broken link[ ·]+\\[\\[truss-include:none\\]\\]" text))
      (should (string-match-p "^ Broken links\n +\\[\\[truss-include:none\\]\\] ← Umbrella$" text))
      (should (string-match-p "^ No grounds\n   Reason \\[no grounds\\][ ·]+Some items are urgent +no grounds: a link or a quote, a TRUSS_LOGIC, or :assumption:$" text))
      (should (string-match-p "^ Missing roles\n   member[ ·]+#move Move to fortnightly +Minor premise$" text))
      (should (string-match-p "RET visit" text)))))

(ert-deftest org-truss-test-board-speaks-english ()
  "The board's own words stay English; the sections a pattern adds to the file
are named in `org-truss-language'."
  (org-truss-test--with-board org-truss-test--file
    (let ((org-truss-language 'ja))
      (org-truss-test--goto-line-with "^ Structure")
      (org-truss-test--answering '("telling › SCQA")
        (org-truss-board-pattern))
      (should (equal (org-truss-test--structure-labels source)
                     '("状況" "複雑化" "問い" "答え" "Sky" "Rain" "Umbrella")))
      (let ((text (buffer-string)))
        (should (string-match-p "^ Structure .*\n (telling › SCQA)$" text))
        (should (string-match-p "├ Complication[ ·]+\\(?:\\[*#[^] ]+]* \\)?複雑化 +複雑化$" text))
        (should (string-match-p "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long +Reviews run long$" text))))))

(ert-deftest org-truss-test-board-leaves-the-root-heading-out ()
  "The structure's own heading names the part, so the board calls it Structure."
  (org-truss-test--with-board (replace-regexp-in-string "^\\* Structure$" "* 構成"
                                                        org-truss-test--file)
    (should (string-match-p "^ Structure " (buffer-string)))
    (should-not (string-match-p "構成" (buffer-string)))
    (should (equal (caar (org-truss--section-choices (org-truss-read source)))
                   "Structure"))))

(ert-deftest org-truss-test-board-shows-the-fields ()
  "Under the title come the brief and the subject, each with its breakdown
and the members right under it, its fields, drawn as any member is, by the
roles they play.  A role the breakdown asks for and no field plays follows
them, and is listed under the part."
  (org-truss-test--with-board org-truss-test--conditions-file
    (should (string-match-p
             (concat "^ Brief  .*\n"
                     " (breakdown › Reader, Question, Response, Constraints)\n"
                     "   Reader[ ·]+Reader +Reader\n"
                     "   Question[ ·]+Their question +Their question\n"
                     "   Response wanted[ ·]+Response wanted +Response wanted\n"
                     "   Constraints —\n\n"
                     " Missing roles\n"
                     "   Brief +Constraints\n\n"
                     " Subject  .*\n"
                     " (breakdown › Premises, Issue, Constraints)\n"
                     "   Issue[ ·]+Issue +Issue\n"
                     "   └ member[ ·]+Nobody checks before a test +Nobody checks before a test\n"
                     "   Constraints[ ·]+Constraints +Constraints\n"
                     "   ├ member[ ·]+#budget No budget this year +No budget this year\n"
                     "   │   ▤ section[ ·]+Constraints\n"
                     "   │   ⏚ source[ ·]+finance, 3 October\n"
                     "   └ member[ ·]+The schedule is fixed +The schedule is fixed\n"
                     "   Premises —\n\n"
                     " Missing roles\n"
                     "   Subject +Premises\n")
             (buffer-string)))
    (org-truss-test--goto-line-with "^   Issue")
    (save-window-excursion
      (org-truss-board-visit)
      (should (equal (org-get-heading t t t t) "Issue")))
    (org-truss-test--goto-line-with "^ └ section[ ·]+Constraints")
    (org-truss-test--answering '("Subject › Constraints › The schedule is fixed")
      (org-truss-board-place))
    ;; Placed, it is given an id to be pointed to by.
    (should (equal (org-truss-cluster-includes
                    (car (org-truss-section-children
                          (org-truss-model-structure (org-truss-read source)))))
                   '("budget" "m1")))
    (should (equal (with-current-buffer source
                     (org-entry-get (org-truss-test--heading-pos "The schedule is fixed") "CUSTOM_ID"))
                   "m1"))))

(ert-deftest org-truss-test-board-parts-take-patterns ()
  "The brief and the subject take patterns as any heading does, and their
members play roles in them.  c on a role their breakdown asks for and no
member plays writes one playing it, where the breakdown lists it; p gives the part another
breakdown, and a member for each role, where the breakdown lists it; a
member playing none of them is marked, and r gives it a role."
  (org-truss-test--with-board org-truss-test--conditions-file
    (let ((headings (lambda ()
                      (with-current-buffer source
                        (org-map-entries (lambda () (org-get-heading t t t t)) "LEVEL=2"))))
          (property (lambda (heading name)
                      (with-current-buffer source
                        (org-entry-get (org-truss-test--heading-pos heading) name)))))
      (org-truss-test--goto-line-with "^   Premises —")
      (org-truss-test--creating '("Tests are random")
        (should (equal (seq-take (seq-drop (funcall headings) 3) 3)
                       '("Tests are random" "Issue" "Constraints")))
        (should (equal (funcall property "Tests are random" "TRUSS_BREAKDOWN_ROLE") "premises")))
      (should (string-match-p "^   Premises[ ·]+Tests are random" (buffer-string)))
      (org-truss-test--goto-line-with "^ Subject ")
      (should (equal (mapcar #'cdr (org-truss--pattern-choices
                                    (org-truss-model-subject (org-truss-read source))))
                     '(reasons deduction induction steps parts
                       what-why-how pros-cons short-long past-present-future 5w1h 6w1h
                       reader-question-response-constraints premises-issue-constraints
                       prep sds scqa sky-rain-umbrella (none . breakdown))))
      (org-truss-test--answering '("breakdown › Pros and cons")
        (org-truss-board-pattern))
      (should (equal (funcall property "Subject" "TRUSS_BREAKDOWN") "pros-cons"))
      (should (equal (seq-drop (funcall headings) 3)
                     '("Pros" "Cons" "Tests are random" "Issue" "Constraints"
                       "Check with a breathalyser" "Constraints")))
      (org-truss-test--goto-line-with "^   Issue \\[no role\\]")
      (should (eq (get-text-property (+ (point) 9) 'face) 'org-truss-attention))
      (should (string-match-p "^ No role\n\\(?:   .*\n\\)*   Issue \\[no role\\][ ·]+Issue +plays no role of breakdown › Pros and cons$"
                              (buffer-string)))
      (org-truss-test--answering '("Cons")
        (org-truss-board-roles))
      (should (equal (funcall property "Issue" "TRUSS_BREAKDOWN_ROLE") "cons"))
      (should (= (count-matches "^   Cons[ ·]" (point-min) (point-max)) 2)))))

(ert-deftest org-truss-test-board-cuts-long-headings ()
  "A heading too long for its room is cut short, so what the reader sees
keeps its column."
  (org-truss-test--with-board (replace-regexp-in-string
                               "Move to fortnightly"
                               "Move to fortnightly, starting next quarter, for every team"
                               org-truss-test--file t t)
    (should (string-match-p "Move to fortnightly, starting[^…\n]*…  Move to fortnightly" (buffer-string)))
    (let ((right (lambda (regexp)
                   ;; The right starts after the line's last gap.
                   (org-truss-test--goto-told-line-with regexp)
                   (end-of-line)
                   (re-search-backward "  \\([^ ]\\)" (line-beginning-position))
                   (- (match-beginning 1) (line-beginning-position)))))
      (should (= (funcall right "told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move")
                 (funcall right "told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long"))))
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move")
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
        (should-not (string-match-p "^ +member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move.*…" board))
        (should (string-match-p (concat "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly, starting next +"
                                        "Move to fortnightly, starting next quarter, for every team\n"
                                        " +(logic › deduction) +quarter, for every team +Hold the review every other week\\.\n")
                                board))))))

(ert-deftest org-truss-test-board-draws-notes-links-as-written ()
  "With entry text shown, a link in a heading's comments is drawn as it is
written, described or not: what it points to is drawn on the line below."
  (let ((org-truss-language 'en))
    (org-truss-test--with "* Subject
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Reviews run long
:PROPERTIES:
:CUSTOM_ID: m1
:END:
* Members
:PROPERTIES:
:TRUSS_PART: members
:TRUSS_LOGIC: reasons
:END:
** Time is wasted
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
# As [[#m1]] and [[moor:6f1c][the minutes]] show.
"
      (let ((board (org-truss-board-text (org-truss-read) t 200)))
        (should (string-match-p "^ +As \\[\\[#m1]] and \\[\\[moor:6f1c]\\[the minutes]] show\\.$" board))))))

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
          (should (equal (org-truss-board-text model nil 100) (org-truss-board-text model nil 300))))))))

(ert-deftest org-truss-test-board-fits-every-line-with-entry-text ()
  "With entry text shown, every line of the board fits the window: a field's
text, a ground, a source, where a member is used, a title, a labelled part
and what a check lists are broken too, and nothing is cut."
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
:TRUSS_BREAKDOWN_ROLE: constraints
:END:
The constraints, LONG.
- An item, LONG
*** A fact, LONG
:PROPERTIES:
:CUSTOM_ID: m1
:END:
[[https://e.x/the-minutes-long][the minutes, LONG]]
*** A question, LONG
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim, LONG
:PROPERTIES:
:CUSTOM_ID: m2
:TRUSS_BREAKDOWN: 6w1h
:END:
[[#m1]]
*** Who does it, LONG
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: who
:END:
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
#+begin_public A title, LONG
#+end_public
- [[truss-include:m2]]
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
                (re-search-forward "^   member[ ·]+\\(?:\\[*#[^] ]+]* \\)?")
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
      (should (string-match-p "^ ├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky .*\n │   • told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long" text))
      (should (string-match-p (concat "^   member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat .*\n"
                                      "   (logic › reasons)\n"
                                      "   │ ▤ Rain[ ·]+Rain\n"
                                      "   │ ↥ member[ ·]+Move to fortnightly\n"
                                      "   │ ⏚ ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long\n"
                                      "   │ ⏚ ground[ ·]+\\[\\[#diff\\]\\] Agenda diff\n"
                                      "   ├ Reason[ ·]+\\(?:\\[*#[^] ]+]* \\)?Agenda diff +noexport$")
                              text))
      ;; The members' tree is drawn in a face of its own, the sections' not.
      (goto-char (point-min))
      (re-search-forward "^   \\(├\\) Reason")
      (should (eq (get-text-property (match-beginning 1) 'face) 'org-truss-branch))
      (re-search-forward "^ \\(├\\) Rain")
      (should-not (get-text-property (match-beginning 1) 'face)))
    (org-truss-test--told)
    (let ((text (buffer-string)))
      (should (string-match-p (concat "^ │   • told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat .*\n"
                                      " │   (logic › reasons)\n"
                                      " │   │ ↥ member[ ·]+Move to fortnightly\n"
                                      " │   │ ⏚ ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long\n"
                                      " │   │ ⏚ ground[ ·]+\\[\\[#diff\\]\\] Agenda diff\n"
                                      " │   ├ Reason[ ·]+\\(?:\\[*#[^] ]+]* \\)?Agenda diff")
                              text))
      (should (string-match-p (concat "^ │   └ Reason \\[no grounds\\][ ·]+Some items are urgent .*\n"
                                      " │     (breakdown › parts)\n"
                                      " │     ├ Part[ ·]+Urgent items go to chat .*\n"
                                      " │     │   ⏚ source[ ·]+team agreement\n"
                                      " │     └ Part[ ·]+Who decides")
                              text)))))

(ert-deftest org-truss-test-board-aligns-the-files-words ()
  "The file's words start in one column, however much the board says first."
  (org-truss-test--with-board org-truss-test--file
    (let ((columns (mapcar (lambda (spec) (org-truss-test--column-of (car spec) (cdr spec)))
                           '(("^ Title" . "Fortnightly reviews")
                             ("├ Sky" . "Sky")
                             ("member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move" . "Move to fortnightly")
                             ("Part[ ·]+Who" . "Who decides what is urgent")
                             ("^   member[ ·]+Lone" . "Lone remark")))))
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
  "After the file's words comes what the reader sees: its heading, or for the
structure the start of the text under it, with links read as their text."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "Rain[ ·]+\\(?:\\[*#[^] ]+]* \\)?Rain +Rain$" text))
      (should (string-match-p "Half the items repeat +Half the items repeat$" text))
      (should (string-match-p "Reason[ ·]+\\(?:\\[*#[^] ]+]* \\)?Agenda diff +noexport$" text))
      (should (string-match-p "Part[ ·]+\\(?:\\[*#[^] ]+]* \\)?Urgent items go to chat +- Urgent items go to chat$" text))))
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
    (let ((column (org-truss-test--column-of "told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat"
                                             "Half the items repeat" t)))
      (forward-line 1)
      (should (looking-at-p " │   (logic › reasons) +Robin keeps raising the same items; +Half of each agenda"))
      (should (= column (progn (search-forward "Robin") (- (current-column) 5)))))
    (org-truss-board-entry-text)
    (should-not (string-match-p "Robin" (buffer-string)))))

(ert-deftest org-truss-test-board-quotes-as-grounds ()
  "Each quotation is a ground of its own, drawn above the sources, and is
left out of the notes shown under its heading.  Drawn whole, its line is
broken to its column."
  (org-truss-test--with-board
      (concat "#+title: T\n* Members\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n"
              "** Approval goes to the head first\n"
              "Read in the manual.\n"
              "#+begin_quote\nThe head approves.\n#+end_quote\n"
              "#+begin_quote\nEvery request waits a week or more before finance looks at its lines.\n"
              "#+end_quote\n"
              "#+begin_quote\nFinance comes after.\n#+end_quote\n"
              "[[file:manual.txt][Manual]]\n")
    (should (string-match-p (concat "⏚ quote[ ·]+The head approves\\.\n"
                                    ".*⏚ quote[ ·]+Every request.*…\n"
                                    ".*⏚ quote[ ·]+Finance comes after\\.\n"
                                    ".*⏚ source.*Manual")
                            (buffer-string)))
    (org-truss-board-entry-text)
    (should (string-match-p "Read in the manual" (buffer-string)))
    (should (string-match-p "⏚ quote[ ·]+Every request[^…\n]*\n +[^⏚\n]*its lines\\." (buffer-string)))
    (should (= (how-many "The head approves" (point-min) (point-max)) 1))
    (should (= (how-many "Finance comes after" (point-min) (point-max)) 1))))

(ert-deftest org-truss-test-board-wraps-a-line ()
  "w draws the line at point whole, as E draws every line, and leaves the
rest on one line; w again, from any of its lines, puts it back.  With entry
text shown, w puts a line on one line instead, and E draws every line one
way again."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-told-line-with "told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
    (org-truss-board-wrap)
    (should (looking-at-p " │   • told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat"))
    (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 1))
    (should (string-match-p "Robin keeps raising[^├]*\n │   ├ Reason[ ·]+\\(?:\\[*#[^] ]+]* \\)?Agenda diff" (buffer-string)))
    (forward-line 1)
    (org-truss-board-wrap)
    (should (looking-at-p " │   • told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat"))
    (should-not (string-match-p "Robin" (buffer-string)))
    (org-truss-board-entry-text)
    (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 2))
    (org-truss-test--goto-told-line-with "told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
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
:TRUSS_BREAKDOWN: premises-issue-constraints
:END:
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: constraints
:END:
*** A summary, LONG
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
**** A fact, LONG
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
# [[https://e.x/s][s]]
# A note under it, LONG.
**** Another fact
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim, LONG
:PROPERTIES:
:TRUSS_BREAKDOWN: 6w1h
:TRUSS_TELLING: sds
:END:
# A note under the claim.
*** Where it is done
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: where
:END:
" t t)))
    (org-truss-test--with text
      (let ((board (org-truss-board-text (org-truss-read) t 120)))
        (should (string-match-p
                 (concat "^   └ member[ ·]+A summary, long enough to +"
                         "A summary, long enough to break in a column this narrow\n"
                         "     (logic › reasons) +break in a column this\n"
                         "     │ +narrow\n"
                         "     ├ Reason[ ·]+A fact, long enough to break +- A fact, long enough to break in a column this narrow\n"
                         "     │ +in a column this narrow\n"
                         "     │ +A note under it, long enough\n"
                         "     │ +to break in a column this\n"
                         "     │ +narrow\\.\n"
                         "     │   ⏚ source[ ·]+s\n"
                         "     └ Reason \\[no grounds\\] +Another fact +- Another fact\n")
                 board))
        (should (string-match-p
                 (concat "^   member[ ·]+A claim, long enough to +"
                         "A claim, long enough to break in a column this narrow\n"
                         " +break in a column this\n"
                         " +narrow\n"
                         "   (breakdown › 6W1H, telling › SDS)\n"
                         "   │ +A note under the claim\\.\n"
                         "   └ Where")
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
:TRUSS_BREAKDOWN: premises-issue-constraints
:END:
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: constraints
:END:
*** A fact, LONG
:PROPERTIES:
:CUSTOM_ID: m1
:END:
[[https://e.x/s][s]]
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim
:PROPERTIES:
:CUSTOM_ID: m2
:TRUSS_LOGIC: reasons
:END:
[[#m1]]
*** A reason
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[https://e.x/s][s]]
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[truss-include:m1]]
*** Later
- [[truss-include:m2]]
" t t)))
    (org-truss-test--with text
      (let ((model (org-truss-read)))
        (dolist (entries '(nil t))
          (let ((board (org-truss-board-text model entries 120)))
            (should (string-match-p
                     (concat "^   member[ ·]+\\(?:\\[*#[^] ]+]* \\)?A claim.*\n"
                             "   (logic › reasons)\n"
                             "   │ ▤ section[ ·]+Later\n"
                             "   │ ⏚ ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?A fact, long enough to.*\n"
                             (if entries "   │ +in a column this narrow\n" "")
                             "   └ ")
                     board))
            (should (string-match-p
                     (concat "^ └ section[ ·]+\\(?:\\[*#[^] ]+]* \\)?Now.*\n"
                             "   │ • told[ ·]+\\(?:\\[*#[^] ]+]* \\)?A fact, long enough to.*\n"
                             (if entries "   │ +in a column this narrow\n" "")
                             "   └ section[ ·]+\\(?:\\[*#[^] ]+]* \\)?Later")
                     board))))))))

(ert-deftest org-truss-test-board-colours-the-reader-s-text ()
  "On the right, a heading looks like one, with or without entry text; the
text under it, shown with entry text, looks like the comments."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--told)
    (progn
      (dolist (entries '(nil t))
        (unless (eq org-truss--entry-text entries) (org-truss-board-entry-text))
        (org-truss-test--goto-line-with "#half Half the items repeat")
        (should (eq (progn (search-forward "Half the items repeat" nil t 2)
                           (get-text-property (match-beginning 0) 'face))
                    'org-truss-reader))
        (org-truss-test--goto-line-with "^ Structure ")
        (should (eq (progn (search-forward "Urgent items go to chat  ")
                           (skip-chars-forward " ")
                           (forward-char 2)
                           (get-text-property (point) 'face))
                    'org-truss-reader)))
      (goto-char (point-min))
      (should (eq (progn (search-forward "Reviews ran past the hour")
                         (get-text-property (match-beginning 0) 'face))
                  'org-truss-dim))
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
    (org-truss-test--answering '("telling › SCQA")
      (org-truss-board-pattern))
    (should (equal (org-truss-test--structure-labels source)
                   '("Situation" "Complication" "Question" "Answer" "Sky" "Rain" "Umbrella")))
    (org-truss-test--goto-line-with "Rain \\[no role\\][ ·]+Rain")
    (should (equal (get-text-property (point) 'help-echo)
                   "Plays no role of telling › SCQA; M-x org-truss-board-roles gives it one"))))

(ert-deftest org-truss-test-board-marks-sections-outside-the-pattern ()
  "A section playing no role of its parent's pattern is marked."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+\\(?:\\[*#[^] ]+]* \\)?Umbrella")
    (with-current-buffer source
      (org-entry-put (org-truss-test--heading-pos "Umbrella") "TRUSS_TELLING_ROLE" "answer"))
    (org-truss-board-redraw)
    (org-truss-test--goto-line-with "└ Answer \\[no role\\][ ·]+Umbrella")
    (should (string-prefix-p "Plays no role of telling › Sky, Rain, Umbrella; "
                             (get-text-property (point) 'help-echo)))))

(ert-deftest org-truss-test-board-says ()
  "S on a section opens its lead to be written, on a line made before the
links it tells members by; let go, the line goes again.  On a heading
telling none, it opens after the heading's text."
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let ((default-directory dir)
          (org-truss-language 'en))
      (save-window-excursion
        (with-temp-buffer
          (org-truss-board))
        (with-current-buffer (get-buffer (format "*truss %s*" (abbreviate-file-name dir)))
          (org-truss-test--goto-line-with "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky")
          (org-truss-board-say)
          (with-current-buffer (org-truss-test--copy)
            (insert "Where we are.")
            (org-truss-test--let-go))
          ;; What the board does before each command.
          (org-truss-board-redraw)
          (should (string-match-p ":TRUSS_TELLING_ROLE: sky\n:END:\n- \\[\\[truss-include:long"
                                  (with-current-buffer org-truss--source (buffer-string))))
          (should-not (buffer-modified-p org-truss--source))
          (org-truss-test--goto-line-with "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky")
          (org-truss-board-say)
          (with-current-buffer (org-truss-test--copy)
            (insert "Where we are.")
            (org-dock-finish))
          (org-truss-board-redraw)
          (should (equal (org-truss-section-body
                          (car (org-truss-section-children
                                (org-truss-model-structure (org-truss-read org-truss--source)))))
                         "Where we are.\n- [[truss-include:long]]"))
          (org-truss-test--goto-line-with "member[ ·]+Lone remark")
          (org-truss-board-say)
          (with-current-buffer (org-truss-test--copy)
            (insert "Said.")
            (org-dock-finish))
          (should (string-match-p "^\\*\\* Lone remark\n+Said\\.\n"
                                  (with-current-buffer org-truss--source (buffer-string)))))))))

(ert-deftest org-truss-test-board-applies-an-argument-pattern ()
  "p on a member gives it an argument pattern."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
    (org-truss-test--answering '("logic › induction")
      (org-truss-board-pattern))
    (should (eq (org-truss-member-logic
                 (org-truss-member-by-label (org-truss-read source) "Half the items repeat"))
                'induction))))

(defun org-truss-test--top ()
  "Return the board above its structure: the title, the purpose and the fields."
  (let ((text (buffer-string)))
    (substring text 0 (string-match "^ Structure" text))))

(ert-deftest org-truss-test-board-folds ()
  "A member holding more than the limit starts folded, saying how many it
holds; z unfolds it.  z among what it holds folds it again, and z on a
member folds what is nested under it.  c into a folded member unfolds it."
  (let ((org-truss-board-fold-limit 1))
    (org-truss-test--with-board org-truss-test--conditions-file
      (should (string-match-p "^   Constraints ▸2[ ·]+Constraints" (buffer-string)))
      (should-not (string-match-p "member[ ·]+#budget No budget this year" (org-truss-test--top)))
      (org-truss-test--goto-line-with "^   Constraints ▸2")
      (org-truss-board-fold)
      (should (string-match-p "^   ├ member[ ·]+#budget No budget this year" (org-truss-test--top)))
      (org-truss-test--goto-line-with "member[ ·]+The schedule is fixed")
      (org-truss-board-fold)
      (should-not (string-match-p "member[ ·]+The schedule is fixed" (org-truss-test--top)))
      (should (looking-at-p "   Constraints ▸2"))
      (org-truss-test--creating '("Tests start at seven")
        (should (string-match-p "member[ ·]+Tests start at seven" (buffer-string)))
        (should (equal (plist-get (org-truss--item) :label) "Tests start at seven")))))
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
    (org-truss-board-fold)
    (should (string-match-p "member ▸5[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat.*\n   member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move"
                            (buffer-string)))
    (org-truss-test--goto-line-with "member ▸5")
    (org-truss-board-fold)
    (should (string-match-p (concat "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat.*\n"
                                    "   (logic › reasons)\n"
                                    "\\(?:   │ [▤↥] .*\n\\)+"
                                    "   │ ⏚ ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long")
                            (buffer-string)))
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long")
    (should-error (org-truss-board-fold) :type 'user-error)))

(ert-deftest org-truss-test-board-folds-sections ()
  "A section folds as a member does: z folds what is under it -- the
sections below and the members its links tell -- and its line says how
many it hides; one holding more than the limit starts folded."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
    (org-truss-board-fold)
    (should (string-match-p "└ Umbrella ▸2[ ·]+Umbrella" (buffer-string)))
    (should-not (string-match-p "• told.*\\[\\[#move\\]\\]" (buffer-string)))
    (org-truss-test--goto-line-with "└ Umbrella ▸2")
    (org-truss-board-fold)
    (should (string-match-p "• told.*\\[\\[#move\\]\\]" (buffer-string))))
  (let ((org-truss-board-fold-limit 1))
    (org-truss-test--with-board org-truss-test--file
      (should (string-match-p "└ Umbrella ▸2[ ·]+Umbrella" (buffer-string)))
      (should (string-match-p "├ Sky[ ·]+Sky" (buffer-string))))))

(defconst org-truss-test--cycle-file "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Top
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** Middle
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_LOGIC: reasons
:END:
**** Leaf                                                       :assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
")

(ert-deftest org-truss-test-board-cycles ()
  "The board starts open.  TAB cycles a line as Org's TAB does a heading:
folded, what is right under it with each of those folded, everything
under it, folded again; S-TAB folds everything, or opens everything."
  (org-truss-test--with-board org-truss-test--cycle-file
    (let ((shown (lambda (label) (string-match-p (concat "[ ·]" label "\\b") (org-truss-test--top)))))
      (should (funcall shown "Leaf"))
      (should-not (string-match-p "▸" (org-truss-test--top)))
      (org-truss-test--goto-line-with "member[ ·]+Top")
      (org-truss-board-cycle)
      (should (string-match-p "member ▸2[ ·]+Top" (org-truss-test--top)))
      (should-not (funcall shown "Middle"))
      (org-truss-board-cycle)
      (should (funcall shown "Middle"))
      (should (string-match-p "Reason ▸1[ ·]+Middle" (org-truss-test--top)))
      (should-not (funcall shown "Leaf"))
      (org-truss-board-cycle)
      (should (funcall shown "Leaf"))
      (org-truss-board-cycle)
      (should (string-match-p "member ▸2[ ·]+Top" (org-truss-test--top)))
      (org-truss-board-cycle-all)
      (should (funcall shown "Leaf"))
      (org-truss-board-cycle-all)
      (should (string-match-p "member ▸2[ ·]+Top" (org-truss-test--top)))
      (org-truss-board-cycle '(4))
      (should (funcall shown "Leaf"))
      (org-truss-board-cycle '(4))
      (should-not (funcall shown "Middle")))))

(ert-deftest org-truss-test-board-starts-folded ()
  "The board starts as an Org file does in overview, and as C-u TAB folds
it: every line with something under it folded, each line on one line."
  (should (eql (eval (car (get 'org-truss-board-fold-limit 'standard-value)) t) 0))
  (let ((org-truss-board-fold-limit 0))
    (org-truss-test--with-board org-truss-test--cycle-file
      (should (string-match-p "member ▸2[ ·]+Top" (org-truss-test--top)))
      (should-not (string-match-p "Middle" (org-truss-test--top)))
      (org-truss-test--goto-line-with "member ▸2[ ·]+Top")
      (org-truss-board-cycle)
      (should (string-match-p "Reason ▸1[ ·]+Middle" (org-truss-test--top))))))

(ert-deftest org-truss-test-board-wraps-every-line ()
  "i draws the line at point whole; with a prefix argument, every line, as
entry text does, and again every line on one."
  (org-truss-test--with-board org-truss-test--cycle-file
    (org-truss-board-wrap '(4))
    (should org-truss--entry-text)
    (org-truss-board-wrap '(4))
    (should-not org-truss--entry-text)))

(ert-deftest org-truss-test-board-reason-told-on-its-line ()
  "A reason stands on what it tells, on its heading's line or in its text:
the member is drawn under it as a ground, in its words and called by its
id, said to have no grounds when it does not hold, and not
besides as a member told.  A heading whose line is the link is drawn as
written, with the part the member is in beside it.  The member's own line
has it once, as built on it."
  (org-truss-test--with-board "* S
:PROPERTIES:
:TRUSS_PART: subject
:END:
** The fact
:PROPERTIES:
:CUSTOM_ID: fact
:END:
[[https://e.x/minutes][minutes]]
** The bare one
:PROPERTIES:
:CUSTOM_ID: bare
:END:
* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Claim
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** [[truss-include:fact]]
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
*** [[truss-include:bare]]
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
*** As the minutes have it
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
- [[truss-include:fact]]
"
    (let* ((text (buffer-string))
           (members (substring text (string-search " Members" text)))
           (subject (substring text 0 (string-search " Members" text))))
      (should (string-match-p "Reason[ ·]+→Subject \\[\\[truss-include:fact\\]\\].*\n.*⏚ ground[ ·]+\\[\\[#fact\\]\\] The fact" members))
      (should (string-match-p "⏚ ground \\[no grounds\\][ ·]+\\[\\[#bare\\]\\] The bare one" members))
      (should (string-match-p "Reason[ ·]+As the minutes have it.*\n.*⏚ ground[ ·]+\\[\\[#fact\\]\\] The fact" members))
      (should-not (string-match-p "•" members))
      (should (string-match-p "↥ Reason[ ·]+\\[\\[truss-include:fact\\]\\]" subject))
      (should-not (string-match-p "▤" subject)))))

(ert-deftest org-truss-test-board-foot ()
  "The foot of the board names the commands that have a key there, and
leaves the rest to be called by name."
  (org-truss-test--with-board org-truss-test--cycle-file
    (let ((text (buffer-string)))
      (should (string-match-p "^see +RET visit  o visit-other-window  TAB cycle  <backtab> cycle-all  i wrap" text))
      (should (string-match-p "^write +m source$" text))
      (should-not (string-match-p "^place" text))
      (should-not (string-match-p " new " text)))))

(ert-deftest org-truss-test-board-visits-a-ground ()
  "RET on a ground goes to the member it names, not to the claim above it."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "⏚ ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long")
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
      (should (eq (funcall face-of "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Check with a breathalyser" "Check with")
                  'org-level-2))
      (should (eq (funcall face-of "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?No budget this year" "No budget") 'org-level-3))
      (with-current-buffer source
        (font-lock-ensure)
        (put-text-property (point-min) (point-max) 'line-prefix "  ")
        (should (equal-including-properties
                     (org-truss-member-label
                      (org-truss-member-by-label (org-truss-read) "No budget this year"))
                     "No budget this year")))
      (org-truss-board-redraw)
      (should (eq (funcall face-of "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?No budget this year" "No budget") 'org-level-3))
      (should-not (text-property-not-all (point-min) (point-max) 'line-prefix nil)))))

(ert-deftest org-truss-test-board-visit-opens-the-blocks ()
  "RET shows the entry it goes to with its blocks open, though they start
folded; the blocks of the headings under it stay as they were."
  (org-truss-test--with-board (replace-regexp-in-string
                               "^\\(Half of each agenda.*\\|We assume most items.*\\)$"
                               "#+begin_comment\n\\1\n#+end_comment" org-truss-test--file)
    (let ((hidden (lambda (text)
                    (with-current-buffer source
                      (save-excursion
                        (goto-char (point-min))
                        (search-forward text)
                        (and (invisible-p (point)) t))))))
      (with-current-buffer source
        (org-fold-hide-block-all))
      (should (funcall hidden "Half of each agenda"))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
      (save-window-excursion
        (org-truss-board-visit))
      (should-not (funcall hidden "Half of each agenda"))
      (should (funcall hidden "We assume most items")))))

(ert-deftest org-truss-test-board-visits-the-brief ()
  "RET on the brief's lines goes to the brief, or to the field the line shows."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^   Reader")
    (save-window-excursion
      (org-truss-board-visit)
      (should (equal (org-get-heading t t t t) "Reader")))
    (org-truss-test--goto-line-with "^ Brief ")
    (save-window-excursion
      (org-truss-board-visit)
      (should (equal (org-get-heading t t t t) "Brief")))
    (org-truss-test--goto-line-with "^ Title")
    (save-window-excursion
      (org-truss-board-visit)
      (should (looking-at-p "#\\+title: Fortnightly reviews")))))

(ert-deftest org-truss-test-board-structure-takes-any-pattern ()
  "p on the Structure line offers a breakdown and a telling pattern.  A
breakdown given to it asks the sections right below to play its roles,
and a section is made for each none plays yet; no telling takes the
telling pattern off."
  (org-truss-test--with-board org-truss-test--file
    (let ((property (lambda (name)
                      (with-current-buffer source
                        (org-entry-get (org-truss-test--heading-pos "Structure") name)))))
      (org-truss-test--goto-line-with "^ Structure ")
      (org-truss-test--answering '("breakdown › Past, present, future")
        (org-truss-board-pattern))
      (should (equal (funcall property "TRUSS_BREAKDOWN") "past-present-future"))
      (should (equal (funcall property "TRUSS_TELLING") "sky-rain-umbrella"))
      (should (equal (org-truss-test--structure-labels source)
                     '("Sky" "Rain" "Umbrella" "Past" "Present" "Future")))
      (should (string-match-p "^ (breakdown › Past, present, future, telling › Sky, Rain, Umbrella)$"
                              (buffer-string)))
      (org-truss-test--goto-line-with "^ Structure ")
      (org-truss-test--answering '("no telling")
        (org-truss-board-pattern))
      (should-not (funcall property "TRUSS_TELLING"))
      (should (string-match-p "^ (breakdown › Past, present, future)$" (buffer-string))))))

(ert-deftest org-truss-test-board-section-gaps ()
  "A section's patterns ask the sections right below it for their roles.
s on a missing role adds a section that plays it; r on a section offers
the roles of the patterns above, those no section plays yet first."
  (org-truss-test--with-board org-truss-test--file
    (with-current-buffer source
      (org-truss-set-pattern (org-truss-test--heading-pos "Umbrella") 'breakdown '5w1h))
    (org-truss-board-redraw)
    (should (string-match-p "└ Umbrella[ ·]+\\(?:\\[*#[^] ]+]* \\)?Umbrella.*\n   (breakdown › 5W1H)\n" (buffer-string)))
    (should (string-match-p "^     Who —$" (buffer-string)))
    (should (string-match-p "^   Umbrella[ ·]+\\(?:\\[*#[^] ]+]* \\)?Umbrella +Who, When, Where, What, Why, How$" (buffer-string)))
    (org-truss-test--goto-line-with "^     When —$")
    (org-truss-test--answering '("When we start")
      (org-truss-board-new-section))
    (with-current-buffer source
      (should (equal (org-entry-get (org-truss-test--heading-pos "When we start") "TRUSS_BREAKDOWN_ROLE")
                     "when")))
    (should-not (string-match-p "^     When —$" (buffer-string)))
    (org-truss-test--goto-line-with "When we start")
    (let (offered)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt table &rest _) (setq offered table) "Who")))
        (org-truss-board-roles))
      (should (equal (seq-take offered 5) '("Who" "Where" "What" "Why" "How"))))
    (with-current-buffer source
      (should (equal (org-entry-get (org-truss-test--heading-pos "When we start") "TRUSS_BREAKDOWN_ROLE")
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
     (let ((edit (org-truss-test--copy)))
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
field or section it goes at the top of the members; the board goes to its
line."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Title")
    (org-truss-test--creating '("Reviews start late")
      (should (equal (org-truss-test--parent-label source "Reviews start late")
                     '("Members" . 2)))
      (should (equal (plist-get (org-truss--item) :label) "Reviews start late"))
      (should (string-match-p "^   member[ ·]+Reviews start late"
                              (buffer-string)))
      (with-current-buffer edit
        (should (equal (buffer-string) "** Reviews start late\n\n"))
        (should (= (point) (+ (point-min) (length "** Reviews start late\n"))))))
    (org-truss-test--goto-line-with "^ Title")
    (should-error (org-truss-test--answering '("Lone remark")
                    (org-truss-board-new))
                  :type 'user-error)))

(ert-deftest org-truss-test-board-creates-where-point-is ()
  "c writes a member last under the heading at point, member or part; on a
missing role one playing it; on a section a member listed there."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long")
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
        (should (string-match-p ":TRUSS_LOGIC_ROLE: minor" (buffer-string)))))
    (org-truss-test--goto-line-with "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky")
    (org-truss-test--creating '("The team grew")
      (should (equal (org-truss-test--parent-label source "The team grew") '("Members" . 2)))
      (let ((model (org-truss-read source)))
        (should (equal (org-truss-member-id (org-truss-member-by-label model "The team grew")) "m1"))
        (should (member "m1"
                        (org-truss-cluster-includes
                         (car (org-truss-section-children (org-truss-model-structure model)))))))))
  (org-truss-test--with-board org-truss-test--conditions-file
    (org-truss-test--goto-line-with "^   Constraints[ ·]+Constraints")
    (org-truss-test--creating '("Tests start at seven")
      (should (equal (org-truss-test--parent-label source "Tests start at seven")
                     '("Constraints" . 3))))
    (org-truss-test--goto-line-with "^ Brief ")
    (org-truss-test--creating '("Who reads it first")
      (should (equal (org-truss-test--parent-label source "Who reads it first") '("Brief" . 2))))))

(ert-deftest org-truss-test-board-new-member-plays-its-role ()
  "c under a member with patterns writes the new member playing a role in
each: the one a pattern has alone, without asking; else the one asked
for.  Under a member with none, nothing is written but the member, and
taking it back leaves the file as it was."
  (org-truss-test--with-board org-truss-test--file
    (let ((role (lambda (label kind)
                  (with-current-buffer source
                    (org-entry-get (org-truss-test--heading-pos label) (org-truss-role-property kind))))))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
      (org-truss-test--creating '("Most agendas match")
        (should (equal (funcall role "Most agendas match" 'logic) "reason")))
      (org-truss-test--goto-line-with "Reason \\[no grounds\\][ ·]+Some items are urgent")
      (org-truss-test--creating '("Releases cannot wait")
        (should (equal (funcall role "Releases cannot wait" 'breakdown) "part")))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--creating '("Our review repeats itself" "Minor premise")
        (should (equal (funcall role "Our review repeats itself" 'logic) "minor")))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Lone remark")
      (org-truss-test--creating '("Said twice")
        (should-not (with-current-buffer source
                      (org-entry-get (org-truss-test--heading-pos "Lone remark") "TRUSS_LOGIC")))
        (should-not (funcall role "Said twice" 'logic)))))
  (org-truss-test--in-directory (list (cons "truss.org" org-truss-test--file))
    (let ((default-directory dir)
          (org-truss-language 'en))
      (save-window-excursion
        (with-temp-buffer
          (org-truss-board))
        (with-current-buffer (get-buffer (format "*truss %s*" (abbreviate-file-name dir)))
          (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Lone remark")
          (org-truss-test--answering '("Said twice")
            (org-truss-board-new))
          (with-current-buffer (org-truss-test--copy)
            (org-truss-test--let-go))
          (with-current-buffer org-truss--source
            (should-not (string-match-p "Said twice" (buffer-string))))
          (should-not (buffer-modified-p org-truss--source)))))))

(ert-deftest org-truss-test-board-marks-grounds-that-do-not-hold ()
  "A ground that does not hold says so on its line, and so does a source
pointing to nothing; each is listed under its check, at the member that
points to it."
  (org-truss-test--with-board (replace-regexp-in-string
                               "^# \\[\\[https://e\\.x/hallway\\]\\[hallway\\]\\]$" "# [[#lone]]\n# [[file:nowhere.pdf][the memo]]"
                               (replace-regexp-in-string "^\\*\\* Lone remark$"
                                                         "** Lone remark\n:PROPERTIES:\n:CUSTOM_ID: lone\n:END:"
                                                         org-truss-test--file))
    (let ((text (buffer-string)))
      (should (string-match-p "⏚ ground \\[no grounds\\][ ·]+\\[\\[#lone\\]\\] Lone remark" text))
      (should (string-match-p "⏚ source \\[not found\\][ ·]+the memo" text))
      (should (string-match-p "^ Weak grounds\n   member[ ·]+#aside Unused aside +\\[\\[#lone\\]\\] has no grounds$" text))
      (should (string-match-p "^ Broken links\n   member[ ·]+#aside Unused aside +\\[\\[file:nowhere\\.pdf\\]\\[the memo\\]\\] not found$" text)))))

(ert-deftest org-truss-test-board-assumptions ()
  "A tags a member :assumption: or takes the tag off.  A reason that lacked
grounds has them then, and the board says so."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "Major premise \\[no grounds\\]")
    (org-truss-board-assume)
    (should (string-match-p "Major premise \\[assumed\\][ ·]+A meeting" (buffer-string)))
    (org-truss-test--goto-line-with "Major premise \\[assumed\\]")
    (org-truss-board-assume)
    (should (string-match-p "Major premise \\[no grounds\\][ ·]+A meeting" (buffer-string)))))

(ert-deftest org-truss-test-board-files-a-member ()
  "f moves a member, with what is nested under it, last under a part or
another member.  Links still find it."
  (org-truss-test--with-board org-truss-test--conditions-file
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?No budget this year")
    (org-truss-test--answering '("Members")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "No budget this year") '("Members" . 2)))
    (should (equal (plist-get (org-truss--item) :label) "No budget this year"))
    (should-not (string-match-p "broken link" (buffer-string)))
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Check with a breathalyser")
    (org-truss-test--answering '("Subject › Constraints: Constraints")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "Check with a breathalyser")
                   '("Constraints" . 3))))
  (org-truss-test--with-board org-truss-test--file
    (let ((model (org-truss-read source)))
      (should-not (assoc "Members › Half the items repeat › Agenda diff"
                         (org-truss--file-choices
                          model (org-truss-member-by-label model "Half the items repeat")))))
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "Half the items repeat")
                   '("Lone remark" . 3)))
    (should (equal (org-truss-test--parent-label source "Who decides what is urgent")
                   '("Some items are urgent" . 5)))))

(ert-deftest org-truss-test-board-draws-includes ()
  "A member's links that tell members are drawn under it, as a section's
are, each one line where it is not opened; one drawn inside what it tells
is one line, marked, since it would never end.  Loops and links that
tell nothing are listed under Broken links, in the part they are in."
  (progn
    (org-truss-test--with-board org-truss-test--includes-file
      (let ((text (buffer-string)))
        (should (string-match-p (concat "   member[ ·]+#move Move to fortnightly +Move to fortnightly\n"
                                        "     ▤ member[ ·]+Under it\n"
                                        "     ▤ section[ ·]+Now\n"
                                        "     • told[ ·]+\\[\\[#long\\]\\] Reviews run long")
                                text))
        (should (string-match-p "^ Broken links\n   member[ ·]+#move Move to fortnightly +\\[\\[truss-include:loop\\]\\] tells it back$"
                                text))
        (should (string-match-p "• broken link[ ·]+\\[\\[truss-include:gone\\]\\]" text))))
    (org-truss-test--with-board org-truss-test--includes-file
      (org-truss-test--told)
      (should (string-match-p "• told ▸2 \\[loop\\][ ·]+\\[\\[#move\\]\\] Move to fortnightly" (buffer-string))))))

(ert-deftest org-truss-test-board-numbers-sections ()
  "A section below one broken down shows on the right the number, the
bullet or the role the reader sees it with, as a member does."
  (org-truss-test--with-board "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_BREAKDOWN: steps
:END:
** Agree
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
** Change the calendar
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
"
    (should (string-match-p "├ Step[ ·]+Agree +1\\. Agree$" (buffer-string)))
    (should (string-match-p "└ Step[ ·]+Change the calendar +2\\. Change the calendar$" (buffer-string)))))

(ert-deftest org-truss-test-board-numbers-steps ()
  "A step is drawn as one, numbered on the right as the reader will see it."
  (org-truss-test--with-board org-truss-test--steps-file
    (let ((text (buffer-string)))
      (should (string-match-p "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Check before every test +Check before every test\n +(breakdown › steps)" text))
      (should (string-match-p "Step[ ·]+\\(?:\\[*#[^] ]+]* \\)?Meet the driver face to face +1\\. Meet the driver face to face$" text))
      (should (string-match-p "Step[ ·]+\\(?:\\[*#[^] ]+]* \\)?Note the reading +noexport$" text))
      (should (string-match-p "Step[ ·]+\\(?:\\[*#[^] ]+]* \\)?Breathe into the checker +2\\. Breathe into the checker$" text))
      (should (string-match-p "Step[ ·]+Check the checker works +3\\. Check the checker works$" text)))))

(ert-deftest org-truss-test-board-draws-parts ()
  "Parts are drawn by the roles they play, with the bullet, or the role, the
reader sees; a role none plays is missing, and c on one writes a member
playing it."
  (org-truss-test--with-board org-truss-test--how-file
    (let ((text (buffer-string)))
      (should (string-match-p "(breakdown › 5W1H)" text))
      (should (string-match-p "Who[ ·]+\\(?:\\[*#[^] ]+]* \\)?The driver's manager +- Who: The driver's manager$" text))
      (should (string-match-p "Step[ ·]+\\(?:\\[*#[^] ]+]* \\)?Meet the driver +1\\. Meet the driver$" text))
      (should (string-match-p "Part[ ·]+\\(?:\\[*#[^] ]+]* \\)?A checker that works +- A checker that works$" text))
      (should (string-match-p "(telling › PREP)" text))
      (should (string-match-p "What —" text)))
    (org-truss-test--goto-line-with "What —")
    (org-truss-test--creating '("Breathe into the checker")
      (should (equal (org-truss-member-roles
                      (org-truss-member-by-label (org-truss-read source) "Breathe into the checker"))
                     '((breakdown . what))))
      (should-not (string-match-p "What —" (buffer-string))))))

(ert-deftest org-truss-test-board-offers-members-by-path ()
  "Members are offered by where they are: from their part, through what
they are nested under, cut short, to their own heading; a step with its
number, a part with its role.  A member comes just before what is
written under it."
  (org-truss-test--with org-truss-test--how-file
    (let ((model (org-truss-read)))
      (should (equal (org-truss--member-path
                      model (org-truss-member-by-label model "Read the checker"))
                     "Members › Check before every … › As follows › step 2: Read the checker"))
      (should (equal (org-truss--member-path
                      model (org-truss-member-by-label model "Someone to check"))
                     "Members › What a check needs › Part: Someone to check"))))
  (org-truss-test--with org-truss-test--conditions-file
    (let* ((model (org-truss-read))
           (names (mapcar #'car (org-truss--file-choices
                                 model (org-truss-member-by-label model "Check with a breathalyser")))))
      (should (equal (seq-drop names (seq-position names "Subject › Constraints: Constraints"))
                     '("Subject › Constraints: Constraints"
                       "Subject › Constraints › No budget this year"
                       "Subject › Constraints › The schedule is fixed"
                       "Members"))))))

(ert-deftest org-truss-test-board-offers-patterns-by-family ()
  "p offers every heading every logic, breakdown and telling pattern; one
written can be taken off.  What a pattern asks for and is not there is put
in, a heading for each role."
  (org-truss-test--with org-truss-test--file
    (let* ((model (org-truss-read))
           (choices (lambda (cluster) (mapcar #'cdr (org-truss--pattern-choices cluster)))))
      (should (equal (funcall choices (org-truss-test--m model "Lone remark"))
                     '(reasons deduction induction steps parts
                       what-why-how pros-cons short-long past-present-future 5w1h 6w1h
                       reader-question-response-constraints premises-issue-constraints
                       prep sds scqa sky-rain-umbrella)))
      (should (equal (last (funcall choices (org-truss-test--m model "Move to fortnightly")))
                     '((none . logic))))
      (should (equal (funcall choices (org-truss-model-structure model))
                     '(reasons deduction induction steps parts what-why-how pros-cons short-long past-present-future 5w1h 6w1h
                       reader-question-response-constraints premises-issue-constraints
                       prep sds scqa sky-rain-umbrella (none . telling))))
      (should (equal (car (rassq 'prep (org-truss--pattern-choices
                                        (org-truss-test--m model "Lone remark"))))
                     "telling › PREP"))))
  (org-truss-test--with-board org-truss-test--file
    (let ((member (lambda () (org-truss-member-by-label (org-truss-read source) "Move to fortnightly"))))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--answering '("telling › PREP")
        (org-truss-board-pattern))
      (should (eq (org-truss-member-logic (funcall member)) 'deduction))
      (should (eq (org-truss-member-telling (funcall member)) 'prep))
      (should (string-match-p "(logic › deduction, telling › PREP)" (buffer-string)))
      (should (equal (mapcar (lambda (m) (cons (org-truss-member-label m) (org-truss-member-roles m)))
                             (org-truss-member-children (funcall member)))
                     '(("A meeting that repeats itself can meet less" (logic . major))
                       ("Point" (telling . point)) ("Reason" (telling . reason))
                       ("Example" (telling . example)) ("Point again" (telling . recap)))))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--answering '("no telling")
        (org-truss-board-pattern))
      (should-not (org-truss-member-telling (funcall member)))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--answering '("logic › reasons")
        (org-truss-board-pattern))
      (should (eq (org-truss-member-logic (funcall member)) 'reasons))
      (should (string-match-p "(logic › reasons)" (buffer-string))))))

(ert-deftest org-truss-test-board-creates-the-next-step ()
  "c writes under the heading at point, last, whatever it is: on a member
broken down into steps, its last step; on a step, a member under the
step.  Under a breakdown of labelled roles it asks which one the new
member plays."
  (org-truss-test--with-board org-truss-test--steps-file
    (let ((steps (lambda ()
                   (org-truss-test--labels
                    (org-truss-member-children
                     (org-truss-member-by-label (org-truss-read source) "Check before every test"))))))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Check before every test")
      (org-truss-test--creating '("Thank the driver")
        (should (equal (car (last (funcall steps))) "Thank the driver"))
        (should (string-match-p "Step[ ·]+\\(?:\\[*#[^] ]+]* \\)?Thank the driver +4\\. Thank the driver"
                                (buffer-string))))
      (org-truss-test--goto-line-with "Step[ ·]+\\(?:\\[*#[^] ]+]* \\)?Meet the driver face to face")
      (org-truss-test--creating '("The law asks to see it")
        (should (equal (org-truss-test--parent-label source "The law asks to see it")
                       '("Meet the driver face to face" . 4))))))
  (org-truss-test--with-board org-truss-test--how-file
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Check before every test")
    (org-truss-test--creating '("A breath test" "What")
      (should (equal (org-truss-test--parent-label source "A breath test")
                     '("Check before every test" . 3)))
      (should (equal (org-truss-member-roles
                      (org-truss-member-by-label (org-truss-read source) "A breath test"))
                     '((breakdown . what)))))))

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
            (org-truss-test--goto-line-with "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky")
            (org-truss-test--answering '("The team grew")
              (org-truss-board-new))
            (with-current-buffer (org-truss-test--copy)
              (should org-dock-mode)
              (should (string-match-p "C-c C-c" (format "%s" header-line-format)))
              (insert "Two joined in May.\n")
              (org-truss-test--let-go))
            (should-not (org-truss-test--copy))
            (should-not (string-match-p "The team grew" (with-current-buffer org-truss--source
                                                          (buffer-string))))
            (should-not (buffer-modified-p org-truss--source))
            (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Lone remark")
            (org-truss-board-edit)
            (with-current-buffer (org-truss-test--copy)
              (goto-char (point-max))
              (insert "Said in passing.\n")
              (org-truss-test--let-go))
            (should-not (buffer-modified-p org-truss--source))
            (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Lone remark")
            (org-truss-board-edit)
            (with-current-buffer (org-truss-test--copy)
              (goto-char (point-max))
              (insert "Said in passing.\n")
              (org-dock-finish))
            (should-not (org-truss-test--copy))
            (should-not (buffer-modified-p org-truss--source))
            (should (string-match-p "\\*\\* Lone remark\n\nSaid in passing\\.\n"
                                    (with-temp-buffer
                                      (insert-file-contents file)
                                      (buffer-string))))))))))

(ert-deftest org-truss-test-init-sets-up-the-directory ()
  "init writes a truss file and puts beside it the directories its head
comment names and, when one is named, the file marking a project,
leaving what is there already.  A file written before gets the line that keeps its attachments
beside it, unsaved."
  (org-truss-test--in-directory
      '(("old/truss.org" . "#+title: Old\n* Members\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n"))
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
        (should-not (buffer-modified-p))
        (should (equal (funcall read "new/truss.org") (buffer-string)))
        (dolist (sub '("new/sources" "new/notes"))
          (should (file-directory-p (expand-file-name sub dir))))
        (should-not (file-exists-p (expand-file-name "new/.project" dir)))
        (let ((org-truss-project-file ".project"))
          (org-truss-init (expand-file-name "old" dir)))
        (should (string-prefix-p "# -*- org-attach-id-dir: \"attach/\"; -*-\n#+title: Old\n"
                                 (buffer-string)))
        (should (buffer-modified-p))
        (should (file-directory-p (expand-file-name "old/sources" dir)))
        (should (equal (funcall read "old/.project") ""))))))

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
            (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Lone remark")
            (org-truss-board-assume)
            (should (string-match-p "^ Title  unsaved" (buffer-string)))
            (should (eq (command-remapping 'save-buffer) #'org-truss-board-save))
            (org-truss-board-save)
            (should-not (string-match-p "unsaved" (buffer-string)))
            (should (string-match-p "Lone remark +:assumption:"
                                    (with-temp-buffer
                                      (insert-file-contents (expand-file-name "truss.org" dir))
                                      (buffer-string))))))))))

(ert-deftest org-truss-test-board-shows-without-leaving ()
  "SPC shows the heading in another window and keeps the board selected."
  (org-truss-test--with-board org-truss-test--file
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (delete-other-windows)
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long")
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
    (org-truss-test--goto-line-with "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky")
    (org-truss-test--answering '("How reviews run now")
      (org-truss-board-rename))
    (should (equal (car (org-truss-test--structure-labels source)) "How reviews run now"))
    (should (string-match-p "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?How reviews run now" (buffer-string)))))

(ert-deftest org-truss-test-board-edits-one-entry ()
  "e takes the line's heading out with what is under it, the headings under
it folded to their lines; the heading stays as it is in the file until the
copy is written back."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
    (save-window-excursion
      (org-truss-board-edit)
      (should org-dock-mode)
      (should (string-prefix-p "** Half the items repeat" (buffer-string)))
      (should (string-match-p "\\*\\*\\* Agenda diff" (buffer-string)))
      (should-not (string-match-p "Move to fortnightly" (buffer-string)))
      (goto-char (point-min))
      (search-forward "Robin keeps")
      (should-not (invisible-p (point)))
      (search-forward "[[https://e.x/agendas")
      (should (invisible-p (point)))
      (goto-char (point-min))
      (end-of-line)
      (insert "\nA note.")
      (should-not (with-current-buffer source
                    (save-excursion (goto-char (point-min)) (search-forward "A note." nil t))))
      (org-dock-finish)
      (should (with-current-buffer source
                (save-excursion (goto-char (point-min)) (search-forward "A note." nil t)))))))

(ert-deftest org-truss-test-board-catches-up ()
  "Selected again after its file changed, the board draws again."
  (org-truss-test--with-board org-truss-test--file
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (with-current-buffer source
        (goto-char (org-truss-test--heading-pos "Sky"))
        (org-edit-headline "Where we are"))
      (org-truss--catch-up (selected-window))
      (should (string-match-p "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Where we are" (buffer-string))))))

(ert-deftest org-truss-test-board-places-in-more-sections ()
  "a on a section tells there a member told elsewhere too: a member can be
told in as many places as want it, and the document tells it in each.
Told there already, nothing changes."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
    (org-truss-test--answering '("Members › Reviews run long")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-cluster-includes (car (org-truss-section-children root)))
                     '("long")))
      (should (equal (org-truss-cluster-includes (nth 2 (org-truss-section-children root)))
                     '("move" "none" "long"))))
    (should (= (with-temp-buffer
                 (insert (org-truss-render (org-truss-read source)))
                 (count-matches "^ *- Reviews run long$" (point-min) (point-max)))
               2))
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (org-truss-test--answering '("Members › Reviews run long")
      (org-truss-board-place))
    (should (equal (org-truss-cluster-includes
                    (car (org-truss-section-children (org-truss-model-structure (org-truss-read source)))))
                   '("long")))))

(ert-deftest org-truss-test-board-places-an-unplaced-member ()
  "a on a section tells there the member chosen, those placed nowhere
offered first; a member placed elsewhere is placed there too, and one
placed there stays put."
  (org-truss-test--with-board org-truss-test--file
    (should (equal (mapcar #'car (seq-take (org-truss--heading-choices (org-truss-read source)) 2))
                   '("Members › Unused aside" "Members › Lone remark")))
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (should (equal (org-truss-cluster-includes
                    (car (org-truss-section-children
                          (org-truss-model-structure (org-truss-read source)))))
                   '("long" "m1")))
    (should-not (string-match-p "^ Not placed\n.*\n   member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Lone remark" (buffer-string)))
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+\\(?:\\[*#[^] ]+]* \\)?Umbrella")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-cluster-includes (car (org-truss-section-children root)))
                     '("long" "m1")))
      (should (equal (org-truss-cluster-includes (nth 2 (org-truss-section-children root)))
                     '("move" "none" "m1"))))
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+\\(?:\\[*#[^] ]+]* \\)?Umbrella")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (should (equal (org-truss-cluster-includes
                    (nth 2 (org-truss-section-children
                            (org-truss-model-structure (org-truss-read source)))))
                   '("move" "none" "m1")))))

(ert-deftest org-truss-test-board-tells-in-any-heading ()
  "a on a member tells the heading chosen inside it, as on a section: a
member, or a section, which the document then tells there as it tells a
section in a list item."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "member[ ·]+#move Move to fortnightly")
    (org-truss-test--answering '("Members › Lone remark")
      (org-truss-board-place))
    (should (equal (org-truss-cluster-includes
                    (org-truss-test--m (org-truss-read source) "Move to fortnightly"))
                   '("m1")))
    (org-truss-test--goto-line-with "member[ ·]+#move Move to fortnightly")
    (org-truss-test--answering '("Structure › Sky › Sky")
      (org-truss-board-place))
    (let ((model (org-truss-read source)))
      (should (equal (org-truss-cluster-includes (org-truss-test--m model "Move to fortnightly"))
                     '("m1" "m2")))
      (should (equal (org-truss-cluster-id (car (org-truss-section-children (org-truss-model-structure model))))
                     "m2"))
      (should (string-match-p "^- Move to fortnightly\n\n  Hold the review every other week\\.\n  - Lone remark\n  - Sky\n\n    - Reviews run long\n"
                              (org-truss-render model))))))

(ert-deftest org-truss-test-board-links-to-sections ()
  "A section is a heading like any other to the links that reach it: b
offers it as a ground, and = goes between it where it is written and the
lines that call it, lit together."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "member[ ·]+#move Move to fortnightly")
    (org-truss-test--answering '("Structure › Sky › Sky")
      (org-truss-board-ground))
    (let ((model (org-truss-read source)))
      (should (equal (org-truss-cluster-refs (org-truss-test--m model "Move to fortnightly"))
                     '("half" "m1")))
      (should (equal (org-truss-cluster-id (car (org-truss-section-children (org-truss-model-structure model))))
                     "m1")))
    ;; A section holds as any heading does: with no grounds of its own, it
    ;; is a weak ground.
    (should (string-match-p "⏚ ground \\[no grounds\\][ ·]+\\[\\[#m1\\]\\] Sky" (buffer-string)))
    (org-truss-test--goto-line-with "⏚ ground \\[no grounds\\][ ·]+\\[\\[#m1\\]\\] Sky")
    (org-truss-board-same)
    (should (looking-at " ├ Sky"))
    (should (seq-some (lambda (o) (eq (overlay-get o 'face) 'org-truss-same))
                      (overlays-in (point-min) (point-max))))))

(ert-deftest org-truss-test-board-places-instead-of-a-broken-link ()
  "a on a broken link places the chosen member where the link stands; where
else it is placed, it stays."
  (org-truss-test--with-board org-truss-test--file
    (let ((links (lambda (n) (org-truss-cluster-includes
                              (nth n (org-truss-section-children
                                      (org-truss-model-structure (org-truss-read source))))))))
      (org-truss-test--goto-line-with "broken link[ ·]+\\[\\[truss-include:none\\]\\]")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-place))
      (should (equal (funcall links 2) '("move" "m1")))
      (should-not (string-match-p "broken link" (buffer-string))))
    ;; A link that names a heading is broken too, and is put right the same way.
    (with-current-buffer source
      (goto-char (point-max))
      (insert "- [[truss-include:*Reviews run long]]\n- [[truss-include:last]]\n"))
    (org-truss-board-redraw)
    (org-truss-test--goto-line-with "broken link[ ·]+\\[\\[truss-include:\\*Reviews run long\\]\\]")
    (org-truss-test--answering '("Members › Reviews run long")
      (org-truss-board-place))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-cluster-includes (car (org-truss-section-children root)))
                     '("long")))
      (should (equal (org-truss-cluster-includes (nth 2 (org-truss-section-children root)))
                     '("move" "m1" "long" "last"))))))

(ert-deftest org-truss-test-board-takes-out-and-deletes ()
  "d takes a member out of the structure and leaves it in the file; D deletes
it from the file, with what is under it and what placed it, leaving the
grounds that named it to show as broken."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-told-line-with "told[ ·]+\\(?:\\[*#[^] ]+]* \\)?Reviews run long")
    (org-truss-board-take-out)
    (let ((model (org-truss-read source)))
      (should (org-truss-member-by-label model "Reviews run long"))
      (should (null (org-truss-cluster-includes
                     (car (org-truss-section-children (org-truss-model-structure model)))))))
    (org-truss-test--goto-line-with "\\(?:member\\|told\\)[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
    (org-truss-test--answering '(nil)
      (org-truss-board-delete))
    (should (org-truss-member-by-label (org-truss-read source) "Half the items repeat"))
    (org-truss-test--goto-line-with "\\(?:member\\|told\\)[ ·]+\\(?:\\[*#[^] ]+]* \\)?Half the items repeat")
    (org-truss-test--answering '(t)
      (org-truss-board-delete))
    (let ((model (org-truss-read source)))
      (should-not (org-truss-member-by-label model "Half the items repeat"))
      (should-not (org-truss-member-by-label model "Agenda diff"))
      (should (null (org-truss-cluster-includes
                     (nth 1 (org-truss-section-children (org-truss-model-structure model))))))
      (should (equal (org-truss-cluster-refs (org-truss-member-by-label model "Move to fortnightly"))
                     '("half"))))
    (should (string-match-p "⏚ broken ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?\\[\\[#half\\]\\]" (buffer-string)))
    (should (string-match-p "^ Broken links\n +member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly +\\[\\[#half\\]\\] not found$"
                            (buffer-string)))))

(ert-deftest org-truss-test-board-grounds ()
  "b makes another member a ground, or no longer one; on a ground's own line
it takes that ground away."
  (org-truss-test--with-board org-truss-test--file
    (let ((grounds (lambda () (org-truss-cluster-refs
                               (org-truss-member-by-label (org-truss-read source) "Move to fortnightly")))))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--answering '("Members › Unused aside")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("half" "aside")))
      (should (string-match-p "⏚ ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?Unused aside" (buffer-string)))
      ;; A member pointed to for the first time is given an id.
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("half" "aside" "m1")))
      (should (with-current-buffer source
                (string-match-p "^Hold the review every other week\\.\n# \\[\\[#aside\\]\\]\n# \\[\\[#m1\\]\\]\n"
                                (buffer-string))))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--answering '("Members › Lone remark")
        (org-truss-board-ground))
      (org-truss-test--goto-line-with "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?Move to fortnightly")
      (org-truss-test--answering '("Members › Half the items repeat")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("aside")))
      (org-truss-test--goto-line-with "⏚ ground[ ·]+\\(?:\\[*#[^] ]+]* \\)?Unused aside")
      (org-truss-board-ground)
      (should (null (funcall grounds)))
      (should-not (with-current-buffer source
                    (string-match-p "^# \\[\\[#\\(?:half\\|aside\\|m1\\)\\]\\]$" (buffer-string)))))))

(ert-deftest org-truss-test-board-unwrap-asks-before-losing ()
  "u asks before discarding text, and does nothing when told no."
  (org-truss-test--with-board (replace-regexp-in-string "^- \\[\\[truss-include:half\\]\\]$"
                                                        "Why it drags.\n- [[truss-include:half]]"
                                                        org-truss-test--file)
    (org-truss-test--goto-line-with "^ Structure")
    (org-truss-test--answering '(nil)
      (org-truss-board-unwrap))
    (should (= 3 (length (org-truss-test--structure-labels source))))
    (org-truss-test--answering '(t)
      (org-truss-board-unwrap))
    (should (null (org-truss-test--structure-labels source)))))

(ert-deftest org-truss-test-board-new-section-and-roles ()
  "s adds a section, asking the role it plays in the pattern above, where
the pattern lists the role; r changes it."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Structure")
    (org-truss-test--answering '("Rain" "More rain")
      (org-truss-board-new-section))
    (should (equal (org-truss-test--structure-labels source) '("Sky" "Rain" "More rain" "Umbrella")))
    (should-not (string-match-p "Out of order" (buffer-string)))
    (org-truss-test--goto-line-with "├ Rain[ ·]+More rain")
    (org-truss-test--answering '("Umbrella")
      (org-truss-board-roles))
    (should (equal (org-truss-section-roles
                    (nth 2 (org-truss-section-children
                            (org-truss-model-structure (org-truss-read source)))))
                   '((telling . umbrella))))))

(ert-deftest org-truss-test-board-keeps-up-with-the-file ()
  "A hand edit to the file is drawn before the next command, which then acts
at once.  Fontifying the file is not an edit.  Only an edit made while a
command is asking makes it draw again instead of acting."
  (org-truss-test--with-board org-truss-test--file
    (let ((umbrella (lambda () (org-truss-cluster-includes
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
      (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
      (org-truss--before-command)
      (should-not (org-truss--stale-p))
      (org-truss-test--answering '("Members › Reviews run long")
        (org-truss-board-place))
      (should (member "long" (funcall umbrella)))
      (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _)
                   (with-current-buffer source
                     (goto-char (point-min))
                     (insert "\n"))
                   "Members › Lone remark")))
        (should-error (org-truss-board-place) :type 'user-error))
      (should (member "long" (funcall umbrella))))))

(ert-deftest org-truss-test-board-orders-headings ()
  "M-down moves a section after its next sibling, and a member where it is
written after its next one, with what is nested under it: an order the
telling pattern does not want is put right from the board."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky")
    (org-truss-board-down)
    (should (equal (org-truss-test--structure-labels source) '("Rain" "Sky" "Umbrella"))))
  (org-truss-test--with-board org-truss-test--telling-text
    (should (string-match-p "Out of order" (buffer-string)))
    (org-truss-test--goto-line-with "Reviews are weekly")
    (org-truss-board-up)
    (org-truss-board-up)
    (org-truss-board-up)
    (org-truss-test--goto-line-with "Half the items repeat")
    (org-truss-board-up)
    (should (equal (org-truss-test--labels
                    (org-truss-member-children
                     (org-truss-member-by-label (org-truss-read source) "We move to fortnightly reviews")))
                   '("Reviews are weekly" "Half the items repeat" "Should we keep meeting weekly"
                     "Robin agrees")))
    (should-not (string-match-p "Out of order" (buffer-string)))))

(ert-deftest org-truss-test-board-refiles-a-section ()
  "f moves a section, with what is under it, last under another section; it
cannot go under itself, and the structure stays where it is."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "├ Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?Sky")
    (org-truss-test--answering '("Structure › Umbrella › Umbrella")
      (org-truss-board-refile))
    (should (equal (org-truss-test--structure-labels source) '("Rain" "Umbrella")))
    (should (equal (org-truss-test--parent-label source "Sky") '("Umbrella" . 3)))
    (should (string-match-p "• told[ ·]+\\[\\[#long\\]\\] Reviews run long" (buffer-string)))
    (org-truss-test--goto-line-with "^ Structure ")
    (should-error (org-truss-board-refile) :type 'user-error)))

(ert-deftest org-truss-test-board-draws-the-parts-in-order ()
  "The subject, the members and the structure each take a part of the board,
in the order the work is done, each followed by what is left to do there.
A part's members are drawn as any member is.  Everywhere a member's right
is what the document tells of it, and outside the structure, lines marked
▤ and ↥ say where it is used."
  (org-truss-test--with-board org-truss-test--clusters-file
    (let ((text (buffer-string)))
      (should (string-match-p
               (concat "^ Subject .*\n"
                       " (breakdown › Premises, Issue, Constraints)\n"
                       "   Premises[ ·]+Premises +Premises\n"
                       "   └ member[ ·]+How many cars we run +How many cars we run\n"
                       "   Constraints[ ·]+Constraints +Constraints\n"
                       "   ├ member[ ·]+#rule The manager checks every driver.* +"
                       "The manager checks every driver before and after driving\n"
                       "   │ (logic › reasons)\n"
                       "   │ │ ▤ Situation[ ·]+Background\n"
                       "   │ │ ↥ member[ ·]+Drivers are checked before and after .*\n"
                       "   │ ├ Reason[ ·]+The rule asks for a check before driv.* +"
                       "The rule asks for a check before driving\n")
               text))
      (should (string-match-p (concat "member[ ·]+\\(?:\\[*#[^] ]+]* \\)?A manager is named.*\n"
                                      "   │   ↥ member[ ·]+The law binds us, so we must check\n"
                                      "   │   ↥ member[ ·]+The rule may apply to us\n")
                              text))
      (should (< (string-match "^ Subject " text) (string-match "^ Members " text)
                 (string-match "^ Structure " text)))
      (should (string-match-p (concat "├ Situation[ ·]+\\(?:\\[*#[^] ]+]* \\)?Background +Background\n"
                                      " │   • told ▸3[ ·]+\\(?:\\[*#[^] ]+]* \\)?The manager checks.* +The manager checks every driver before and after driving\n"
                                      " └ Answer")
                              text))
      (should (string-match-p "Step[ ·]+\\(?:\\[*#[^] ]+]* \\)?The driver blows into the tester +1\\. The driver blows" text)))))

(ert-deftest org-truss-test-board-patterns-in-the-subject ()
  "A member of the subject is offered the patterns a member of the members
is; c on the subject's own line writes a member under it, and on a member
with reasons another."
  (org-truss-test--with org-truss-test--clusters-file
    (let ((model (org-truss-read)))
      (should (equal (last (mapcar #'cdr (org-truss--pattern-choices
                                          (org-truss-test--m model "The manager checks every driver before and after driving")))
                           2)
                     '(sky-rain-umbrella (none . logic))))))
  (org-truss-test--with-board org-truss-test--clusters-file
    (org-truss-test--goto-line-with "^ Subject ")
    (org-truss-test--creating '("Checks take a minute")
      (should (equal (org-truss-test--parent-label source "Checks take a minute") '("Subject" . 2))))
    (org-truss-test--goto-line-with "member[ ·]+#rule The manager checks")
    (org-truss-test--creating '("The check may be made by phone")
      (should (equal (org-truss-test--parent-label source "The check may be made by phone")
                     '("The manager checks every driver before and after driving" . 4)))
      (should (string-match-p "Reason \\[no grounds\\][ ·]+The check may be made by phone"
                              (buffer-string))))))

(ert-deftest org-truss-test-board-shows-what-is-unfinished ()
  "A section the file has too late is marked, saying which it is below, and
listed under the structure; a heading playing no role of the pattern above
is marked, and listed under its part."
  (org-truss-test--with-board org-truss-test--unfinished-file
    (let ((text (buffer-string)))
      (should (string-match-p "^ ├ Sky ⚠[ ·]+\\(?:\\[*#[^] ]+]* \\)?空 " text))
      (should (equal (get-text-property (string-match "^ ├ Sky ⚠" text) 'help-echo text)
                     "Sky, Rain, Umbrella tells it before Rain, which is above it in the file"))
      (should (string-match-p "^ Out of order\n   Sky[ ·]+\\(?:\\[*#[^] ]+]* \\)?空 +below Rain$" text))
      (should (string-match-p "^ └ section \\[no role\\][ ·]+Notes for later" text))
      (should (eq (get-text-property (string-match "\\[no role\\][ ·]+Notes for later" text) 'face text)
                  'org-truss-attention))
      (should (string-match-p "^ No role\n   section \\[no role\\][ ·]+Notes for later +plays no role of telling › Sky, Rain, Umbrella$"
                              text))
      (should (string-match-p "└ member \\[no role\\][ ·]+Example +Example$" text))
      (should (string-match-p "^ No role\n   member \\[no role\\][ ·]+Example +plays no role of telling › PREP$"
                              text)))))

(ert-deftest org-truss-test-board-tells-aspects-of-reasons ()
  "In the structure a reason playing a role of a breakdown shows it on the
right, as the reader is told it: in the breakdown's list."
  (org-truss-test--with-board "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** We move
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_LOGIC: reasons
:TRUSS_BREAKDOWN: pros-cons
:END:
*** Less time in meetings
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_BREAKDOWN_ROLE: pros
:END:
[[https://e.x/the-calendar][the calendar]]
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
- [[truss-include:move]]
"
    (org-truss-test--goto-told-line-with "Less time in meetings")
    (should (string-match-p "Less time in meetings +- Pros: Less time in meetings$"
                            (buffer-substring (point) (line-end-position))))))

(ert-deftest org-truss-test-board-opens-members-where-told ()
  "O opens the members a section lists under it, with their uses, grounds
and gaps, and folds them where they are written; O again opens them where
written and lists them on one line in the structure.  Point stays on the
member, where it is opened.  The mode line says which."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^   member ·+ #half")
    (org-truss-board-fold)
    (org-truss-board-order)
    (should (equal mode-name "Truss told"))
    (should (looking-at " │   • told[ ·]+\\[\\[#half\\]\\] Half the items repeat"))
    (should (string-match-p "^   member ▸5[ ·]+#half Half the items repeat +Half the items repeat$"
                            (buffer-string)))
    (should (string-match-p (concat "^ └ Umbrella.*\n"
                                    "     • told[ ·]+\\[\\[#move\\]\\] Move to fortnightly.*\n"
                                    "     (logic › deduction)\n"
                                    "     │ ⏚ ground[ ·]+\\[\\[#half\\]\\] Half the items repeat\n"
                                    "     └ Major premise \\[no grounds\\].*\n"
                                    "       Minor premise —\n")
                            (buffer-string)))
    (org-truss-board-order)
    (should (equal mode-name "Truss"))
    (should (looking-at "   member[ ·]+#half Half the items repeat"))
    (should (string-match-p "^ │   • told ▸5[ ·]+\\[\\[#half\\]\\]" (buffer-string))))
  (org-truss-test--with-board org-truss-test--clusters-file
    (org-truss-test--told)
    (should (string-match-p "^   ├ member ▸3[ ·]+#rule The manager checks every driver"
                            (buffer-string)))
    (should (string-match-p "^ │   • told[ ·]+\\[\\[#rule\\]\\] The manager checks every driver.*\n │   (logic › reasons)\n"
                            (buffer-string)))))

(ert-deftest org-truss-test-board-tells-where-it-is-written ()
  "Where a member is written, its right is what the document tells of it:
its words, its steps numbered, its aspects labelled; in the face of what
is not told while nothing tells it.  Lines under it name the headings
whose links tell it, marked ▤, and the members it is a ground of, marked ↥, cut to the middle, and go to them; the mouse on
the mark says what it means; the member commands do not take them for
the member."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p (concat "^   member[ ·]+#long Reviews run long +Reviews run long\n"
                                      "     ▤ Sky[ ·]+Sky\n"
                                      "     ↥ member[ ·]+Half the items repeat\n")
                              text))
      (should (string-match-p "Major premise \\[no grounds\\][ ·]*A meeting that .*  - A meeting that repeats itself can meet less$"
                              text))
      (org-truss-test--goto-line-with "^   member[ ·]+Lone remark +\\(Lone remark\\)$")
      (should (eq (get-text-property (match-beginning 1) 'face) 'org-truss-untold))
      (org-truss-test--goto-line-with "^   member[ ·]+#long Reviews run long +\\(Reviews run long\\)$")
      (should-not (eq (get-text-property (match-beginning 1) 'face) 'org-truss-untold))
      (org-truss-test--goto-line-with "^     ↥ member")
      (should (string-prefix-p "Built on it: this member stands on the member above"
                               (get-text-property (+ (point) 5) 'help-echo)))
      (should-error (org-truss-board-delete) :type 'user-error)
      (save-window-excursion
        (org-truss-board-visit)
        (should (equal (org-get-heading t t t t) "Half the items repeat")))))
  (let ((org-truss-board-middle-width 24))
    (org-truss-test--with-board org-truss-test--clusters-file
      (should (string-match-p "^   │ ⏚ ground[ ·]+\\[\\[#rule\\]\\] The manager checks ev…$" (buffer-string)))
      (should (string-match-p "Step[ ·]+The driver blows into…  1\\. The driver blows into the tester$"
                              (org-truss-test--top))))))

(ert-deftest org-truss-test-board-names-members-by-id ()
  "A member is named by its CUSTOM_ID at the end of the left, before its
heading: #m where it is written, [[#m]] where a link or a ground calls it.
Nested under a member a section calls, a member is not called itself, and
is named by nothing; one with no id, by nothing anywhere.  The heading
starts in the same column all the same."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "^   member ·+ #half Half the items repeat " text))
      (should (string-match-p "^   │ ⏚ ground ·+ \\[\\[#long\\]\\] Reviews run long$" text))
      (should (string-match-p "^ │   • told ▸5[ ·]+\\[\\[#half\\]\\] Half the items repeat " text))
      (should (string-match-p "^   member ·+ Lone remark +Lone remark$" text))
      (should (= (org-truss-test--column-of "^   member ·+ #half" "Half the items repeat")
                 (org-truss-test--column-of "^   member ·+ Lone remark" "Lone remark"))))
    (org-truss-test--told)
    (let ((text (buffer-string)))
      (should (string-match-p "^ │   • told ·+ \\[\\[#half\\]\\] Half the items repeat " text))
      (should (string-match-p "^ │   ├ Reason ·+ Agenda diff " text)))))

(ert-deftest org-truss-test-board-goes-to-the-same-member ()
  "= on a line calling a member goes to where it is written; there, to the
next call after the one come from, and round; on a member shown under one
a section calls, to where it is written as well."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-told-line-with "told ·+ \\[\\[#half\\]\\]")
    (org-truss-board-same)
    (should (looking-at "   member ▸5 ·+ #half Half the items repeat"))
    (org-truss-board-same)
    (should (looking-at "     │ ⏚ ground[ ·]+\\[\\[#half\\]\\]"))
    (org-truss-board-same)
    (should (looking-at "   member ▸5 ·+ #half"))
    (org-truss-board-same)
    (should (looking-at " │   • told ·+ \\[\\[#half\\]\\]"))
    ;; Where it is written is folded into the member it is nested under,
    ;; which is opened where told; it is unfolded.
    (org-truss-test--goto-told-line-with "Reason ·+ Agenda diff")
    (org-truss-board-same)
    (should (looking-at "   ├ Reason ·+ #diff Agenda diff"))))

(ert-deftest org-truss-test-board-unfolds-to-the-same-member ()
  "= unfolds a member that hides where the member is written."
  (let ((org-truss-board-fold-limit 1))
    (org-truss-test--with-board org-truss-test--conditions-file
      (should-not (string-match-p "#budget No budget" (buffer-string)))
      (org-truss-test--goto-told-line-with "\\[\\[#budget\\]\\]")
      (org-truss-board-same)
      (should (looking-at "   ├ member ·+ #budget No budget this year")))))

(ert-deftest org-truss-test-board-lights-the-same-member ()
  "The lines naming the member on the line at point are lit, but that line:
where it is written, where it is called, the lines it takes below its own."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-told-line-with "told ·+ \\[\\[#half\\]\\]")
    (org-truss--light-same)
    (let ((lit (mapcar (lambda (overlay)
                         (buffer-substring (overlay-start overlay) (1- (overlay-end overlay))))
                       org-truss--same-overlays)))
      (should (seq-some (lambda (line) (string-match-p "#half Half the items repeat" line)) lit))
      (should (seq-some (lambda (line) (string-match-p "⏚ ground[ ·]+\\[\\[#half\\]\\]" line)) lit))
      (should-not (seq-some (lambda (line) (string-match-p "^ │   • told" line)) lit)))
    (org-truss-test--goto-line-with "^ Title")
    (org-truss--light-same)
    (should-not org-truss--same-overlays)))

(ert-deftest org-truss-test-board-of-one-heading ()
  "In an Org file that is no truss file, the board is of the heading at
point alone, or of the nearest above it with a pattern: its patterns, what
is under it in its places, and what they lack, without the parts of a
document.  A pattern applied there puts in a heading for each place."
  (org-truss-test--in-directory
      (list (cons "notes.org"
                  (concat "#+title: Notes\n"
                          "* New approval rules\n"
                          "** The head approves\n"
                          "* Something else\n")))
    (let ((org-truss-language 'en))
      (save-window-excursion
        (with-current-buffer (find-file-noselect (expand-file-name "notes.org" dir))
          (goto-char (point-min))
          (search-forward "New approval")
          (org-truss-board))
        (should (get-buffer "*truss notes.org › New approval rules*"))
        (set-buffer "*truss notes.org › New approval rules*")
        (should (string-match-p "^ Heading  one heading" (buffer-string)))
        (should-not (string-match-p "Something else\\|Misplaced\\|no structure part" (buffer-string)))
        (org-truss-test--goto-line-with "[a-z]+[ ·]+\\(?:\\[*#[^] ]+]* \\)?New approval rules")
        (org-truss-test--answering '("breakdown › 5W1H")
          (org-truss-board-pattern))
        (should (string-match-p "breakdown › 5W1H" (buffer-string)))
        (with-current-buffer org-truss--source
          (goto-char (point-min))
          (should (equal (org-entry-get (search-forward "New approval") "TRUSS_BREAKDOWN") "5w1h"))
          (should (re-search-forward "^\\*\\* Who\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: who\n" nil t)))
        ;; From under it, the board is of the heading with the pattern.
        (with-current-buffer org-truss--source
          (goto-char (point-min))
          (search-forward "The head approves")
          (should (equal (org-with-point-at (org-truss--root-here) (org-get-heading t t t t))
                         "New approval rules")))))))

(ert-deftest org-truss-test-agent-told-the-patterns ()
  "A heading taken out with patterns tells an agent their roles, as the
values of the role properties and the titles of their placeholders, how
one is written, and which must have grounds."
  (org-truss-test--in-directory
      (list (cons "notes.org" "* Rules\n:PROPERTIES:\n:TRUSS_BREAKDOWN: pros-cons\n:END:\n** Pros\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: pros\n:END:\n"))
    (let ((org-truss-language 'en)
          got)
      (with-current-buffer (find-file-noselect (expand-file-name "notes.org" dir))
        (let ((org-dock-agent-function (lambda (r) (setq got r))))
          (with-current-buffer (save-current-buffer (org-dock-heading (point-min) :display nil))
            (org-dock-ask-agent)
            (let ((text (with-temp-buffer (insert-file-contents (plist-get got :request))
                                          (buffer-string))))
              (should (string-match-p "^## Truss$" text))
              (should (string-match-p "pros-cons (TRUSS_BREAKDOWN)" text))
              (should (string-match-p "Roles: pros \\[Pros\\], cons \\[Cons\\]" text))
              (should (string-match-p "title one sentence that states what plays the role" text))
              (should (string-match-p "Under TRUSS_LOGIC, give each such subheading grounds" text)))))))))

(ert-deftest org-truss-test-apply-a-pattern-in-the-file ()
  "A pattern is applied from the file as from the board: in a file that is
no truss file to the heading at point, or to one under a heading with a
pattern; in a truss file to the member the heading is."
  (let ((org-truss-language 'en))
    (org-truss-test--with "* Rules\n** Who\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: who\n:END:\n* Else\n"
      (search-forward "Rules")
      (org-truss-test--answering '("breakdown › 5W1H")
        (org-truss-apply-pattern))
      (goto-char (point-min))
      (should (equal (org-entry-get (point) "TRUSS_BREAKDOWN") "5w1h"))
      (should (re-search-forward "^\\*\\* When\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: when\n" nil t))
      (should-not (re-search-forward "^\\*\\* Who$" nil t))
      (goto-char (point-min))
      (search-forward "** Who")
      (org-truss-test--answering '("breakdown › steps")
        (org-truss-apply-pattern))
      (should (equal (org-entry-get (point) "TRUSS_BREAKDOWN") "steps"))
      (goto-char (point-min))
      (search-forward "* Else")
      (should-not (org-entry-get (point) "TRUSS_BREAKDOWN")))
    (org-truss-test--with org-truss-test--file
      (search-forward "** Reviews run long")
      (org-truss-test--answering '("logic › deduction")
        (org-truss-apply-pattern))
      (should (equal (org-entry-get (point) "TRUSS_LOGIC") "deduction"))
      (should (re-search-forward "^\\*\\*\\* Major premise\n" nil t)))))

(defconst org-truss-test--steps
  (concat "** Procedure\n:PROPERTIES:\n:TRUSS_BREAKDOWN: steps\n:END:\n"
          "*** First step\n:PROPERTIES:\n:TRUSS_BREAKDOWN_ROLE: step\n:END:\n")
  "A heading with steps, and a step under it.")

(defun org-truss-test--request-of (file heading)
  "Return what an agent is told of HEADING in FILE, taken out by org-dock."
  (let* (got
         (org-dock-agent-function (lambda (request) (setq got request))))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-min))
      (re-search-forward (concat "^\\*+ " (regexp-quote heading) "$"))
      (with-current-buffer (save-current-buffer (org-dock-heading (line-beginning-position)))
        (org-dock-ask-agent)
        (prog1 (with-temp-buffer (insert-file-contents (plist-get got :request)) (buffer-string))
          (org-dock-abort))))))

(ert-deftest org-truss-test-dock-request-the-same-words ()
  "A copy out of a truss file and one out of any other file are told the
same: the patterns there, the one above the copy's heading among them,
what the heading plays in it, and how to check the copy.  Where the rest
of the rules are only of a truss file; nothing of a heading with no
pattern near it."
  (org-truss-test--in-directory
      (list (cons "doc/truss.org"
                  (concat "#+title: T\n* Members\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n"
                          org-truss-test--steps))
            (cons "project.org" (concat "* Tasks\n" org-truss-test--steps "* Log\n")))
    (let ((truss (org-truss-test--request-of (expand-file-name "doc/truss.org" dir) "First step"))
          (project (org-truss-test--request-of (expand-file-name "project.org" dir) "First step")))
      (dolist (text (list truss project))
        (should (string-match-p "^- steps (TRUSS_BREAKDOWN): .*\n  Roles: step \\[Step\\]$" text))
        (should (string-match-p "plays step in the steps of \"Procedure\", above the copy" text))
        (should (string-match-p "-f org-truss-batch-check [^ ]*First-step\\.org$" text)))
      (should (string-match-p "rules of the file are in the comment at its head" truss))
      (should-not (string-match-p "comment at its head" project))
      (should-not (string-match-p "## Truss"
                                  (org-truss-test--request-of (expand-file-name "project.org" dir) "Log"))))))

(ert-deftest org-truss-test-check-copy ()
  "A copy is checked written back where it came from: what is in it by its
own lines, and outside it only what it brings about, by the file's lines
as they are."
  (org-truss-test--in-directory
      (list (cons "truss.org"
                  (concat "#+title: T\n* Members\n:PROPERTIES:\n:TRUSS_PART: members\n:END:\n"
                          "** Base\n:PROPERTIES:\n:CUSTOM_ID: m1\n:END:\n[[file:x.txt]]\n"
                          "** Claim\n:PROPERTIES:\n:TRUSS_LOGIC: reasons\n:END:\n"
                          "*** A fact\n:PROPERTIES:\n:TRUSS_LOGIC_ROLE: reason\n:END:\n[[#m1]]\n"
                          "*** Bare reason\n:PROPERTIES:\n:TRUSS_LOGIC_ROLE: reason\n:END:\n"))
            (cons "x.txt" "x\n"))
    (let ((file (expand-file-name "truss.org" dir)))
      (with-current-buffer (find-file-noselect file)
        (goto-char (point-min))
        (re-search-forward "^\\*\\* Base$")
        (with-current-buffer (save-current-buffer (org-dock-heading (line-beginning-position)))
          (goto-char (point-min))
          (re-search-forward ":CUSTOM_ID: m1")
          (replace-match ":CUSTOM_ID: m9\n:TRUSS_BREAKDOWN: steps")
          (save-buffer)
          (let ((report (org-truss-check-copy buffer-file-name (org-dock-copy-origin buffer-file-name))))
            (should (string-match-p (concat "^" (regexp-quote buffer-file-name) ":1: Base -- lacks") report))
            (should (string-match-p (concat "^" (regexp-quote file) ":15: A fact -- \\[\\[#m1\\]\\] not found") report))
            (should-not (string-match-p "Bare reason" report)))
          (org-truss-test--let-go))))))

(ert-deftest org-truss-test-check-a-file-that-is-no-truss-file ()
  "Any other Org file is checked as boards of one heading read it, each
heading with a pattern and none above it with one."
  (org-truss-test--with
      (concat "* Tasks\n** Procedure\n:PROPERTIES:\n:TRUSS_BREAKDOWN: steps\n:END:\n"
              "* Plan\n:PROPERTIES:\n:TRUSS_LOGIC: reasons\n:END:\n"
              "** Why\n:PROPERTIES:\n:TRUSS_LOGIC_ROLE: reason\n:END:\n")
    (let ((report (org-truss--check-in "p.org" (org-truss--check-groups-here))))
      (should (string-match-p "^p\\.org:2: Procedure -- lacks TRUSS_BREAKDOWN_ROLE step" report))
      (should (string-match-p "^p\\.org:10: Why -- no grounds" report)))))

(provide 'org-truss-board-test)

;;; org-truss-board-test.el ends here

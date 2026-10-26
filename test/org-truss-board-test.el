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

(defconst org-truss-test--links
  "\\(?:  ⏚.*\\)?"
  "What a member's line may end with: the members it stands on that it cannot.")

(defconst org-truss-test--marks
  "\\(?:[↪+◌✓✗?][^ ]* +\\)*"
  "The marks that may come just before a line's words, each with a space.
Where the member its words link to is written, and the thin column's;
see `org-truss-board-where-marks' and `org-truss-board-quote-marks'.")

(defconst org-truss-test--gap
  (concat " *" org-truss-test--marks "\\(?:- \\)?")
  "What may come between a line's dots and its words.
The marks before them, and the bullet its words open with; a test of
what a line says need not spell them.")

(defun org-truss-test--id-at (regexp)
  "Return what the mouse on the dots of the board line matching REGEXP says.
The ID the line names its member by; see `org-truss--with-id'."
  (save-excursion
    (org-truss-test--goto-line-with regexp)
    ;; Two dots, not the one between two roles.
    (re-search-forward "··" (line-end-position))
    (get-text-property (1- (point)) 'help-echo)))

(defun org-truss-test--goto-line-with (regexp &optional from)
  "Put point on the first board line matching REGEXP, after FROM if given."
  (goto-char (or from (point-min)))
  (unless (re-search-forward regexp nil t)
    (error "No line matching %s" regexp))
  (beginning-of-line))

(defun org-truss-test--goto-member (words &optional from)
  "Put point on the first board line of the member whose words begin with WORDS.
Its own line, found by the member it stands for rather than by how it is
drawn, after FROM if given."
  (goto-char (or from (point-min)))
  (let (found)
    (while (and (not found) (not (eobp)))
      (let ((item (get-text-property (point) 'org-truss-item)))
        (if (and item (org-truss--head-p item)
                 (string-prefix-p words (or (plist-get item :words) "")))
            (setq found t)
          (forward-line 1))))
    (unless found
      (error "No line of a member saying %s" words))))

(defmacro org-truss-test--answering (answers &rest body)
  "Run BODY with every prompt answered, in turn, from ANSWERS."
  (declare (indent 1))
  `(let ((queue ,answers))
     (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) (pop queue)))
               ((symbol-function 'completing-read-multiple) (lambda (&rest _) (pop queue)))
               ((symbol-function 'read-string) (lambda (&rest _) (pop queue)))
               ((symbol-function 'y-or-n-p) (lambda (&rest _) (pop queue))))
       ,@body)))

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
       (ignore edit)
       ,@body)))

(defun org-truss-test--opened-where-included ()
  "Draw the board with the members Structure includes opened where included."
  (unless (eq org-truss--board-order 'included)
    (setq org-truss--board-order 'included)
    (org-truss-board-redraw)))

(defun org-truss-test--goto-structure-line-with (regexp)
  "Put point on the first line of the board's Structure matching REGEXP.
Members are drawn above it too, where they are worked on; in Structure
they are drawn as the output document has them, opened there once the
board opens them where they are included, as this does."
  (org-truss-test--opened-where-included)
  (org-truss-test--goto-line-with "^ Structure ")
  (org-truss-test--goto-line-with regexp (point)))

(defun org-truss-test--goto-structure-member (words)
  "Put point on the first line in the board's Structure of the member saying WORDS.
As `org-truss-test--goto-member' finds one, the board opened where it
includes; see `org-truss-test--goto-structure-line-with'."
  (org-truss-test--opened-where-included)
  (org-truss-test--goto-line-with "^ Structure ")
  (org-truss-test--goto-member words (point)))

(defun org-truss-test--column-of (regexp text &optional in-structure)
  "Return the column TEXT starts at, after a gap, on a line matching REGEXP.
The first such line; in Structure when IN-STRUCTURE."
  (if in-structure
      (org-truss-test--goto-structure-line-with regexp)
    (org-truss-test--goto-line-with regexp))
  (re-search-forward (concat "[ ·][ ·]" org-truss-test--gap "\\(" (regexp-quote text) "\\)")
                     (line-end-position))
  (goto-char (match-beginning 1))
  (current-column))

(defun org-truss-test--structure-labels (source)
  (mapcar #'org-truss-member-words
          (org-truss-member-supports (org-truss-model-structure (org-truss-read source)))))

(ert-deftest org-truss-test-board-draws ()
  "The board shows sections, members by the roles they play, missing roles
and what is undone."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p (concat "├ Sky[ ·]+" org-truss-test--gap "Sky$") text))
      (should (string-match-p "^ Structure .*\n △ (telling › Sky, Rain, Umbrella)\n ├ Sky" text))
      (should (string-match-p
               (concat "member[ ·]+" org-truss-test--gap "Move to fortnightly"
                       org-truss-test--links "\n +[△▲] (logic › deduction)$")
               text))
      (should (string-match-p "Minor premise —" text))
      (should (string-match-p "broken link[ ·]+\\[\\[truss-include:none\\]\\]" text))
      (should (string-match-p "^ Broken links\n +\\[\\[truss-include:none\\]\\] ← Umbrella$" text))
      (should (string-match-p "^ No grounds\n   Reason \\[no grounds\\][ ·]+Some items are urgent +no grounds: a link or a quote, a TRUSS_LOGIC, or :assumption:$" text))
      (should (string-match-p "^ Missing roles\n   member[ ·]+Move to fortnightly +Minor premise$" text))
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
        (should (string-match-p "^ Structure .*\n [△▲] (telling › SCQA)$" text))
        (should (string-match-p (concat "├ Complication[ ·]+" org-truss-test--gap "複雑化$") text))
        (should (string-match-p (concat "member[ ·]+" org-truss-test--gap "Reviews run long"
                                        org-truss-test--links "$")
                                text))))))

(ert-deftest org-truss-test-board-leaves-the-root-heading-out ()
  "The structure's own heading names the part, so the board calls it Structure."
  (org-truss-test--with-board (replace-regexp-in-string "^\\* Structure$" "* 構成"
                                                        org-truss-test--file)
    (should (string-match-p "^ Structure " (buffer-string)))
    (should-not (string-match-p "構成" (buffer-string)))
    (should (equal (caar (org-truss--structure-choices (org-truss-read source)))
                   "Structure"))))

(ert-deftest org-truss-test-board-says-what-a-line-is-for ()
  "? says in the echo area what the member at point is for: a role of
Brief's breakdown, on its member and on its line missing, and a part."
  (let ((org-truss-language 'en)
        said)
    (cl-letf (((symbol-function 'message) (lambda (_ &rest args) (setq said (car args)))))
      (org-truss-test--with-board org-truss-test--conditions-file
        (let ((org-truss-board-fold-limit nil))
          (org-truss-board-redraw)
          (org-truss-test--goto-line-with "^   Reader[ ·]")
          (org-truss-board-guide)
          (should (equal said "Who reads it, and what do they already know?"))
          (org-truss-test--goto-line-with "^   Constraints —")
          (org-truss-board-guide)
          (should (string-prefix-p "What the output document must keep to" said))
          (org-truss-test--goto-line-with "^ Brief ")
          (org-truss-board-guide)
          (should (string-prefix-p "What the output document must satisfy." said)))))))

(ert-deftest org-truss-test-board-shows-the-fields ()
  "Under the title come the brief and the subject, each with its breakdown
and the members right under it, its fields, drawn as any member is, by the
roles they play.  A role the breakdown asks for and no field plays follows
them, and is listed under the part."
  (org-truss-test--with-board org-truss-test--conditions-file
    (should (string-match-p
             (concat "^ Brief  .*\n"
                     " △ (breakdown › Reader, Question, Response, Constraints)\n"
                     "   Reader[ ·]+Reader\n"
                     "   Question[ ·]+Their question\n"
                     "   Response wanted[ ·]+Response wanted\n"
                     "   Constraints —\n\n"
                     " Missing roles\n"
                     "   Brief +Constraints\n\n"
                     " Subject  .*\n"
                     " △ (breakdown › Past, present, future)\n"
                     "   Present[ ·]+Issue\n"
                     "   └ member[ ·]+Nobody checks before a test\n"
                     "   Future[ ·]+Constraints\n"
                     "   ├ member[ ·]+No budget this year\n"
                     "   │   ⏚ source[ ·]+finance, 3 October\n"
                     "   └ member[ ·]+The schedule is fixed\n"
                     "   Past —\n\n"
                     " Missing roles\n"
                     "   Subject +Past\n")
             (buffer-string)))
    (org-truss-test--goto-line-with "^   Present")
    (save-window-excursion
      (org-truss-board-visit)
      (should (equal (org-get-heading t t t t) "Issue")))
    (org-truss-test--goto-line-with "^ └ member[ ·]+Constraints")
    (org-truss-test--answering '("Subject › Constraints › The schedule is fixed")
      (org-truss-board-include))
    ;; Placed, it is given an id to be pointed to by.
    (should (equal (org-truss-member-includes
                    (car (org-truss-member-supports
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
      (org-truss-test--goto-line-with "^   Past —")
      (org-truss-test--creating '("Tests are random")
        (should (equal (seq-take (seq-drop (funcall headings) 3) 3)
                       '("Tests are random" "Issue" "Constraints")))
        (should (equal (funcall property "Tests are random" "TRUSS_BREAKDOWN_ROLE") "past")))
      (should (string-match-p "^   Past[ ·]+Tests are random" (buffer-string)))
      (org-truss-test--goto-line-with "^ Subject ")
      (should (equal (mapcar #'cdr (org-truss--pattern-choices
                                    (org-truss-model-subject (org-truss-read source))))
                     '(reasons deduction induction steps parts
                       what-why-how pros-cons short-long past-present-future 5w1h 6w1h
                       reader-question-response-constraints
                       interpretation-action prep sds scqa sky-rain-umbrella (none . breakdown))))
      (org-truss-test--answering '("breakdown › Pros and cons")
        (org-truss-board-pattern))
      (should (equal (funcall property "Subject" "TRUSS_BREAKDOWN") "pros-cons"))
      (should (equal (seq-drop (funcall headings) 3)
                     '("Pros" "Cons" "Tests are random" "Issue" "Constraints"
                       "Check with a breathalyser" "Constraints")))
      (org-truss-test--goto-line-with "^   Present \\[no role\\]")
      (should (eq (get-text-property (+ (point) 11) 'face) 'org-truss-attention))
      (should (string-match-p "^ No role\n\\(?:   .*\n\\)*   Present \\[no role\\][ ·]+Issue +plays no role of breakdown › Pros and cons$"
                              (buffer-string)))
      (org-truss-test--answering '("Cons")
        (org-truss-board-roles))
      (should (equal (funcall property "Issue" "TRUSS_BREAKDOWN_ROLE") "cons"))
      (should (= (count-matches "^   Cons[ ·]+\\(?:Cons\\|Issue\\)$"
                                (point-min) (point-max))
                 2)))))

(ert-deftest org-truss-test-board-cuts-long-headings ()
  "A heading too long for its room, on one line, is cut short at the
window's edge, the whole of it in the tooltip."
  (org-truss-test--with-board (replace-regexp-in-string
                               "Move to fortnightly"
                               "Move to fortnightly, starting next quarter, for every team"
                               org-truss-test--file t t)
    (let ((org-truss-board-middle-width 40))
      (org-truss-board-redraw))
    (should (string-match-p (concat "Move to fortnightly, starting[^…\n]*…" org-truss-test--links "$")
                            (buffer-string)))
    (org-truss-test--goto-member "Move")
    (re-search-forward "Move to")
    (should (equal (get-text-property (point) 'help-echo)
                   "Move to fortnightly, starting next quarter, for every team"))))

(ert-deftest org-truss-test-board-breaks-long-headings-with-entry-text ()
  "Drawn whole, a heading too long for its room is broken onto the lines
below instead of cut short, its patterns beside the rest of it, and its
text after it."
  (let ((org-truss-language 'en)
        (text (replace-regexp-in-string
               "Move to fortnightly"
               "Move to fortnightly, starting next quarter, for every team"
               org-truss-test--file t t)))
    (org-truss-test--with text
      (let ((board (org-truss-board-text (org-truss-read) t 70)))
        (should-not (string-match-p (concat "^ +member[ ·]+" org-truss-test--gap "Move.*…") board))
        (should (string-match-p (concat "member[ ·]+" org-truss-test--gap "Move to fortnightly, starting next\n"
                                        " +[△▲] (logic › deduction) +quarter, for every team\n"
                                        " +│ +Hold the review every other week\\.\n")
                                board))))))

(ert-deftest org-truss-test-board-draws-notes-links-as-written ()
  "Drawn whole, a link in a heading's comments is drawn as it is written,
described or not, after the # that keeps it in the file: what it points
to is drawn on the line below."
  (let ((org-truss-language 'en))
    (org-truss-test--with "* Subject
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Reviews run long
:PROPERTIES:
:CUSTOM_ID: m1
:END:
* Message
:PROPERTIES:
:TRUSS_PART: message
:TRUSS_LOGIC: reasons
:END:
** Time is wasted
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
# As [[#m1]] and [[moor:6f1c][the minutes]] show.
"
      (let ((board (org-truss-board-text (org-truss-read) t 200)))
        (should (string-match-p "^ +# As \\[\\[#m1]] and \\[\\[moor:6f1c]\\[the minutes]] show\\.$" board))))))

(ert-deftest org-truss-test-board-fits-entry-text-to-the-window ()
  "Drawn whole, a member's text breaks at the window's edge, or at a width
set for the middle; on one line nothing is broken."
  (let ((org-truss-language 'en)
        (whole "Reviews ran past the hour eight times this quarter\\.$"))
    (org-truss-test--with org-truss-test--file
      (let ((model (org-truss-read)))
        (should-not (string-match-p whole (org-truss-board-text model t 70)))
        (should (string-match-p "Reviews ran past the hour eight\n.* times this quarter\\.$"
                                (org-truss-board-text model t 70)))
        (should (string-match-p whole (org-truss-board-text model t 200)))
        (let ((org-truss-board-middle-width 40))
          (should (equal (org-truss-board-text model t 120) (org-truss-board-text model t 300)))
          (should (equal (org-truss-board-text model nil 100) (org-truss-board-text model nil 300))))))))

(ert-deftest org-truss-test-board-fits-every-line-with-entry-text ()
  "Drawn whole, every line of the board fits the window: a field's text, a
ground, a source, where a member is used, a title, a labelled part and
what a check lists are broken too, and nothing is cut."
  (let* ((org-truss-language 'en)
         (org-truss-board-middle-width nil)
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
* Message
:PROPERTIES:
:TRUSS_PART: message
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
  "Right of the board's own words, the file's words take the window to its
edge, and a heading longer is cut short there; a width set for the file's
words fixes it."
  (let ((org-truss-language 'en)
        (long "Move to fortnightly, starting next quarter, for every team in the building"))
    (org-truss-test--with (replace-regexp-in-string "Move to fortnightly" long org-truss-test--file t t)
      (let* ((model (org-truss-read))
             (cut-at
              (lambda (width)
                (with-temp-buffer
                  (insert (org-truss-board-text model nil width))
                  (goto-char (point-min))
                  ;; Cut short, with what it links to after it, to the edge.
                  (re-search-forward (concat "member[ ·]+Move to fort[^\n]*…"))
                  (end-of-line)
                  (current-column)))))
        (should (= (funcall cut-at 60) 59))
        (should (= (funcall cut-at 80) 79))
        (should-not (string-match-p "member[ ·]+Move to fortnightly[^\n]*…" (org-truss-board-text model nil 200)))
        (let ((org-truss-board-middle-width 30))
          (should (= (funcall cut-at 200) (funcall cut-at 80))))))))

(ert-deftest org-truss-test-board-views-the-document ()
  "v shows the document as x would write it, and the board keeps it current."
  (org-truss-test--with-board org-truss-test--file
    (save-window-excursion
      (org-truss-board-view)
      (should (equal (with-current-buffer org-truss--view (buffer-string))
                     (org-truss-render-document (org-truss-read source))))
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
      (should (string-match-p (concat "^ ├ Sky[ ·]+" org-truss-test--gap "Sky\n │   • included[ ·]+"
                                      org-truss-test--gap "Reviews run long")
                              text))
      (should (string-match-p (concat "^   member[ ·]+Half the items repeat\n"
                                      "   ▲ (logic › reasons)\n"
                                      "   ├ Reason \\[noexport\\][ ·]+Agenda diff$")
                              text))
      ;; The members' tree is drawn in a face of its own, the sections' not.
      (goto-char (point-min))
      (re-search-forward "^   \\(├\\) Reason")
      (should (eq (get-text-property (match-beginning 1) 'face) 'org-truss-branch))
      (re-search-forward "^ \\(├\\) Rain")
      (should-not (get-text-property (match-beginning 1) 'face)))
    (org-truss-test--opened-where-included)
    (let ((text (buffer-string)))
      (should (string-match-p (concat "^ │   • included[ ·]+" org-truss-test--gap "Half the items repeat\n"
                                      " │   ▲ (logic › reasons)\n"
                                      " │   │ ⏚ reason[ ·]+" org-truss-test--marks "Reviews run long\n"
                                      " │   ├ Reason \\[noexport\\][ ·]+" org-truss-test--gap "Agenda diff")
                              text))
      (should (string-match-p (concat "^ │   └ Reason \\[no grounds\\][ ·]+- Some items are urgent\n"
                                      " │     △ (breakdown › parts)\n"
                                      " │     ├ Part[ ·]+- Urgent items go to chat\n"
                                      " │     │   ⏚ source[ ·]+team agreement\n"
                                      " │     └ Part[ ·]+- Who decides")
                              text)))))

(ert-deftest org-truss-test-board-aligns-the-files-words ()
  "The file's words start in one column, however much the board says first."
  (org-truss-test--with-board org-truss-test--file
    (let ((columns (mapcar (lambda (spec) (org-truss-test--column-of (car spec) (cdr spec)))
                           `(("^ Title" . "Fortnightly reviews")
                             ("├ Sky" . "Sky")
                             (,(concat "member[ ·]+" org-truss-test--gap "Move") . "Move to fortnightly")
                             ("Part[ ·]+- Who" . "- Who decides what is urgent")
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
  "The file's words are what the reader sees, links read as their text: a
member of a list opens with its bullet, and a member the output document
leaves out is marked so."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p (concat "Rain[ ·]+" org-truss-test--gap "Rain$") text))
      (should (string-match-p (concat "Half the items repeat" org-truss-test--links "$") text))
      (should (string-match-p (concat "Reason \\[noexport\\][ ·]+" org-truss-test--gap "Agenda diff"
                                      org-truss-test--links "$")
                              text))
      (should (string-match-p (concat "Part[ ·]+" org-truss-test--gap "- Urgent items go to chat$") text)))
    (org-truss-test--goto-line-with "Reason \\[noexport\\]")
    (search-forward "Agenda diff")
    (should (eq (car (get-text-property (match-beginning 0) 'face)) 'org-truss-outside))))

(defun org-truss-test--show-all ()
  "Draw every line of the board whole, as S-TAB's last step does."
  (org-truss--show-all 'whole))

(ert-deftest org-truss-test-board-shows-entry-text ()
  "Drawn whole, what is under each heading goes below its line, in the
file's column: what the reader sees, then the comments, after their #.
The line naming its pattern stays right under it, the text starting
beside it, or below when the pattern's words run into its column."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--show-all)
    (let ((column (org-truss-test--column-of (concat "included[ ·]+" org-truss-test--gap "Half the items repeat")
                                             "- Half the items repeat" t)))
      (forward-line 1)
      (should (looking-at-p " │   ▲ (logic › reasons) +Half of each agenda repeats"))
      (should (= column (progn (search-forward "Half of each") (- (current-column) 12))))
      (should (re-search-forward "^ │   │ +# Robin keeps raising the same" nil t)))
    (org-truss--show-all 'open)
    (should-not (string-match-p "Robin" (buffer-string)))))

(ert-deftest org-truss-test-board-heading-that-includes ()
  "A member of Structure whose words are an include link alone is the
member it includes: the board reads it as that member's words, drawn
whole or not, with no line under it naming it again, and where that
member is written it is counted as used."
  (org-truss-test--with-board (org-truss-skeleton "T")
    (dolist (whole '(nil t))
      (when whole
        (org-truss-test--show-all))
      (let ((text (buffer-string)))
        (should (string-match-p "├ Rain[ ·]+↪Message Interpretation\n └ Umbrella" text))
        (should (string-match-p "^   Interpretation[ ·]+Interpretation$" text))
        (should (equal (org-truss-test--id-at "^   Interpretation[ ·]+Interpretation$") "#m2"))
        (should-not (string-match-p "\\[\\[truss-include:m2\\]\\]" text))))))

(ert-deftest org-truss-test-board-draws-the-chain ()
  "Opened where included, Structure brings the trusses it includes, and
they the members they stand on, down to the sources, in one tree; what
it brings is left out where it is written.  A member whose words are an
include link alone stands for the member it includes, which brings what
it has below its line, with no line of its own."
  (org-truss-test--with-board "* S
:PROPERTIES:
:TRUSS_PART: subject
:END:
** The fact
:PROPERTIES:
:CUSTOM_ID: fact
:END:
[[https://e.x/minutes][minutes]]
** Unused
* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Claim
:PROPERTIES:
:CUSTOM_ID: claim
:TRUSS_LOGIC: reasons
:END:
*** [[truss-include:fact]]
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** [[truss-include:claim]]
"
    (let ((org-truss-board-fold-limit nil))
      (org-truss-test--opened-where-included)
      (let ((text (buffer-string)))
        (should (string-match-p "^ Subject .*\n   member[ ·]+Unused\n\n" text))
        (should (string-match-p "^ Message .*\n\n" text))
        (should (string-match-p (concat " └ member[ ·]+↪Message +Claim\n"
                                        "   △ (logic › reasons)\n"
                                        "   └ Reason[ ·]+↪Subject +- The fact\n"
                                        "       ⏚ source[ ·]+minutes\n")
                                text))
        (should-not (string-match-p "• included\\|⏚ reason" text)))))
  ;; A reason's grounds are reasons by a link: included there in the
  ;; output document, or pointed to and left out of it there.
  (org-truss-test--with-board "* S
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Over
:PROPERTIES:
:CUSTOM_ID: over
:END:
[[https://e.x/minutes][minutes]]
** Repeats
:PROPERTIES:
:CUSTOM_ID: rep
:END:
[[https://e.x/minutes][minutes]]
* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Claim
:PROPERTIES:
:CUSTOM_ID: claim
:TRUSS_LOGIC: reasons
:END:
*** It drags on
It runs over: [[truss-include:over]]
*** It repeats
[[#rep]]
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** [[truss-include:claim]]
"
    (let ((org-truss-board-fold-limit nil))
      (org-truss-test--opened-where-included)
      (let ((text (buffer-string)))
        (should (string-match-p (concat "   ├ Reason[ ·]+- It drags on\n"
                                        "   │   • reason[ ·]+" org-truss-test--gap "Over\n"
                                        "   │     ⏚ source[ ·]+minutes\n"
                                        "   └ Reason[ ·]+- It repeats\n"
                                        "       ⏚ reason[ ·]+" org-truss-test--marks "Repeats\n")
                                text))
        (should (equal (org-truss-test--id-at "• reason[ ·]+") "[[#over]]"))
        (should (equal (org-truss-test--id-at "⏚ reason[ ·]+") "[[#rep]]"))))))

(ert-deftest org-truss-test-board-quotes-as-grounds ()
  "Each quotation is a ground of its own, drawn above the sources, and is
left out of the notes shown under its heading.  Drawn whole, its line is
broken to its column."
  (let ((org-truss-board-middle-width 40))
  (org-truss-test--with-board
      (concat "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_PART: message\n:END:\n"
              "** Approval goes to the head first\n"
              "Read in the manual.\n"
              "#+begin_quote\nThe head approves.\n#+end_quote\n"
              "#+begin_quote\nEvery request waits a week or more before finance looks at its lines.\n"
              "#+end_quote\n"
              "#+begin_quote\nFinance comes after.\n#+end_quote\n"
              "[[file:manual.txt][Manual]]\n")
    (should (string-match-p (concat "⏚ quote[ ·]+" org-truss-test--marks "The head approves\\.\n"
                                    ".*⏚ quote[ ·]+" org-truss-test--marks "Every request.*…\n"
                                    ".*⏚ quote[ ·]+" org-truss-test--marks "Finance comes after\\.\n"
                                    ".*⏚ source.*Manual")
                            (buffer-string)))
    ;; The manual is not there to look in: the quotes are not looked for.
    (should (string-match-p "⏚ quote[ ·]+\\? The head approves\\.$" (buffer-string)))
    (org-truss-test--show-all)
    (should (string-match-p "Read in the manual" (buffer-string)))
    (should (string-match-p (concat "⏚ quote[ ·]+" org-truss-test--marks "Every request[^…\n]*\n +[^⏚\n]*its lines\\.")
                            (buffer-string)))
    (should (= (how-many "The head approves" (point-min) (point-max)) 1))
    (should (= (how-many "Finance comes after" (point-min) (point-max)) 1)))))

(ert-deftest org-truss-test-board-cycles-a-member-whole ()
  "TAB on an open member draws it and all under it whole, with their text;
again, it folds; again, its own text is shown whole, and the members right
under it are one line each.  From any line it brings below it, TAB cycles
the member.  On a member with nothing under it, TAB draws it whole, or on
one line again."
  (org-truss-test--with-board org-truss-test--file
    (let ((half (concat "included[ ·]+" org-truss-test--gap "Half the items repeat")))
      (org-truss-test--goto-structure-line-with half)
      (org-truss-board-cycle)
      (should (looking-at-p (concat " │   • " half)))
      (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 1))
      (should (= (how-many "We assume most items" (point-min) (point-max)) 1))
      (forward-line 2)
      (org-truss-board-cycle)
      (should (looking-at-p (concat " │   • included ▸[0-9]+[ ·]+" org-truss-test--gap "Half the items repeat")))
      (should-not (string-match-p "Robin" (buffer-string)))
      (org-truss-board-cycle)
      (should (= (how-many "Robin keeps raising" (point-min) (point-max)) 1))
      (should (string-match-p "Robin keeps raising[^└]*\n │   └ Reason \\[no grounds\\] ▸2" (buffer-string)))
      (should-not (string-match-p "We assume most items" (buffer-string))))
    (org-truss-test--goto-line-with "^   member[ ·]+Lone remark")
    (let ((org-truss-board-middle-width 6))
      (org-truss-board-redraw)
      (should (looking-at-p ".*Lone …$"))
      (org-truss-board-cycle)
      (should (looking-at-p ".*Lone\n +remark$"))
      (org-truss-board-cycle)
      (should (looking-at-p ".*Lone …$")))))

(ert-deftest org-truss-test-board-cycles-a-check-and-structure-whole ()
  "TAB on a line a check lists draws it whole, what the check says below
its words, or on one line again; on the Structure line, it draws the
output document's opening below it, or takes it away."
  (let ((org-truss-board-middle-width 30))
    (org-truss-test--with-board (replace-regexp-in-string
                                 ":TRUSS_TELLING: sky-rain-umbrella\n:END:\n"
                                 "\\&This is how the reviews will run.\n"
                                 org-truss-test--file t)
      (org-truss-test--goto-line-with "^ No grounds")
      (forward-line 1)
      (should (looking-at-p ".*Some items are…  no grounds: a link"))
      (org-truss-board-cycle)
      (should (looking-at-p ".*Some items are urgent\n +no grounds: a link"))
      (org-truss-board-cycle)
      (should (looking-at-p ".*Some items are…  no grounds: a link"))
      (should-not (string-match-p "This is how" (buffer-string)))
      (org-truss-test--goto-line-with "^ Structure ")
      (org-truss-board-cycle)
      (should (string-match-p "^ Structure .*\n △ (telling › Sky, Rain, Umbrella).*\n?[ │]*This is how the reviews"
                              (buffer-string)))
      (org-truss-board-cycle)
      (should-not (string-match-p "This is how" (buffer-string))))))

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
:TRUSS_BREAKDOWN: past-present-future
:END:
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: future
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
* Message
:PROPERTIES:
:TRUSS_PART: message
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
                 (concat "^   └ member[ ·]+A summary, long enough to\n"
                         "     △ (logic › reasons) +break in a column this narrow\n"
                         "     ├ Reason[ ·]+- A fact, long enough to break\n"
                         "     │ +in a column this narrow\n"
                         "     │ +# A note under it, long enough\n"
                         "     │ +# to break in a column this\n"
                         "     │ +# narrow\\.\n"
                         "     │   ⏚ source[ ·]+s\n"
                         "     └ Reason \\[no grounds\\][ ·]+- Another fact\n")
                 board))
        (should (string-match-p
                 (concat "^   member[ ·]+A claim, long enough to break\n"
                         " +in a column this narrow\n"
                         "   [△▲] (breakdown › 6W1H, telling › SDS)\n"
                         "   │ +# A note under the claim\\.\n"
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
:TRUSS_BREAKDOWN: past-present-future
:END:
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: future
:END:
*** A fact, LONG
:PROPERTIES:
:CUSTOM_ID: m1
:END:
[[https://e.x/s][s]]
* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** A claim
:PROPERTIES:
:CUSTOM_ID: m2
:TRUSS_LOGIC: reasons
:END:
[[#m1]]
[[https://e.x/s][s]]
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
                     (concat "^   member[ ·]+" org-truss-test--gap "A claim\n"
                             "   △ (logic › reasons)\n"
                             "   │ ⏚ source[ ·]+s\n"
                             "   └ ")
                     board))
            (should (string-match-p
                     (concat "^ └ member[ ·]+" org-truss-test--gap "Now.*\n"
                             "   │ • included[ ·]+" org-truss-test--gap "A fact, long enough to.*\n"
                             (if entries "\\(?:   │ +[a-z].*\n\\)+" "")
                             "   └ member[ ·]+" org-truss-test--gap "Later")
                     board))))))))

(ert-deftest org-truss-test-board-colours-the-reader-s-text ()
  "Drawn whole, the text under a heading that the reader sees is in the
face of body text, and the comments, which stay in the file, are dimmed."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--opened-where-included)
    (org-truss-test--show-all)
    (goto-char (point-min))
    (should-not (progn (search-forward "Reviews ran past the hour")
                       (get-text-property (match-beginning 0) 'face)))
    (goto-char (point-min))
    (should-not (progn (search-forward "Half of each agenda")
                       (get-text-property (match-beginning 0) 'face)))
    (goto-char (point-min))
    (should (eq (progn (search-forward "# Robin keeps")
                       (get-text-property (match-beginning 0) 'face))
                'org-truss-dim))))

(ert-deftest org-truss-test-board-draws-pictures ()
  "Drawn whole, a picture linked on a line of its own is drawn in its
column, as wide as the column, on as many lines as it is high, each holding
a slice of it, the slices meeting.  Where no picture can be shown, and on
one line, a link to a file is its name."
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
                 (line (org-truss--lay-out (org-truss--line "" (car slices)) 10)))
            ;; Ten columns to the file's words, then the slice.
            (should (equal (car (get-text-property 10 'display line)) '(slice 0 0 150 10)))
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
    (org-truss-test--goto-member "Umbrella")
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
          (org-truss-test--goto-member "Sky")
          (org-truss-board-say)
          (with-current-buffer (org-truss-test--copy)
            (insert "Where we are.")
            (org-truss-test--let-go))
          ;; What the board does before each command.
          (org-truss-board-redraw)
          (should (string-match-p ":TRUSS_TELLING_ROLE: sky\n:END:\n- \\[\\[truss-include:long"
                                  (with-current-buffer org-truss--source (buffer-string))))
          (should-not (buffer-modified-p org-truss--source))
          (org-truss-test--goto-member "Sky")
          (org-truss-board-say)
          (with-current-buffer (org-truss-test--copy)
            (insert "Where we are.")
            (org-dock-finish))
          (org-truss-board-redraw)
          (should (equal (org-truss-member-body
                          (car (org-truss-member-supports
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
    (org-truss-test--goto-member "Half the items repeat")
    (org-truss-test--answering '("logic › induction")
      (org-truss-board-pattern))
    (should (eq (org-truss-member-logic
                 (org-truss-member-by-words (org-truss-read source) "Half the items repeat"))
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
      (should (string-match-p "^   Future ▸2[ ·]+Constraints" (buffer-string)))
      (should-not (string-match-p "member[ ·]+No budget this year" (org-truss-test--top)))
      (org-truss-test--goto-line-with "^   Future ▸2")
      (org-truss-board-fold)
      (should (string-match-p "^   ├ member[ ·]+No budget this year" (org-truss-test--top)))
      (org-truss-test--goto-line-with "member[ ·]+The schedule is fixed")
      (org-truss-board-fold)
      (should-not (string-match-p "member[ ·]+The schedule is fixed" (org-truss-test--top)))
      (should (looking-at-p "   Future ▸2"))
      (org-truss-test--creating '("Tests start at seven")
        (should (string-match-p "member[ ·]+Tests start at seven" (buffer-string)))
        (should (equal (plist-get (org-truss--item) :words) "Tests start at seven")))))
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-member "Half the items repeat")
    (org-truss-board-fold)
    (should (string-match-p (concat "member ▸5[ ·]+" org-truss-test--gap "Half the items repeat.*\n   member[ ·]+"
                                    org-truss-test--gap "Move")
                            (buffer-string)))
    (org-truss-test--goto-line-with "member ▸5")
    (org-truss-board-fold)
    (should (string-match-p (concat "member[ ·]+" org-truss-test--gap "Half the items repeat.*\n"
                                    "   ▲ (logic › reasons)\n"
                                    "   ├ Reason")
                            (buffer-string)))
    (org-truss-test--goto-member "Reviews run long")
    (should-error (org-truss-board-fold) :type 'user-error)))

(ert-deftest org-truss-test-board-folds-sections ()
  "A section folds as a member does: z folds what is under it -- the
sections below and the members its links tell -- and its line says how
many it hides; one holding more than the limit starts folded."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
    (org-truss-board-fold)
    (should (string-match-p "└ Umbrella ▸2[ ·]+Umbrella" (buffer-string)))
    (should-not (string-match-p "• included.*Move to fortnightly" (buffer-string)))
    (org-truss-test--goto-line-with "└ Umbrella ▸2")
    (org-truss-board-fold)
    (should (string-match-p "• included.*Move to fortnightly" (buffer-string))))
  (let ((org-truss-board-fold-limit 1))
    (org-truss-test--with-board org-truss-test--file
      (should (string-match-p "└ Umbrella ▸2[ ·]+Umbrella" (buffer-string)))
      (should (string-match-p "├ Sky[ ·]+Sky" (buffer-string))))))

(defconst org-truss-test--cycle-file "* M
:PROPERTIES:
:TRUSS_PART: message
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
open, everything under it whole, folded, what is right under it with each
of those folded, everything again; S-TAB folds everything, opens
everything on one line, or draws everything whole, in turn."
  (org-truss-test--with-board org-truss-test--cycle-file
    (let ((shown (lambda (label) (string-match-p (concat "[ ·]" label "\\b") (org-truss-test--top))))
          (all (lambda (state) (seq-every-p (lambda (item) (eq (org-truss--state item) state))
                                            (org-truss--drawn-folds)))))
      (should (funcall shown "Leaf"))
      (should-not (string-match-p "▸" (org-truss-test--top)))
      (org-truss-test--goto-line-with "member[ ·]+Top")
      (org-truss-board-cycle)
      (should (funcall shown "Leaf"))
      (should (eq (org-truss--state (org-truss--item)) 'whole))
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
      (should (funcall all 'open))
      (org-truss-board-cycle-all)
      (should (funcall all 'whole))
      (org-truss-board-cycle-all)
      (should (string-match-p "member ▸2[ ·]+Top" (org-truss-test--top)))
      (org-truss-board-cycle '(4))
      (should (funcall shown "Leaf"))
      (org-truss-board-cycle '(4))
      (should (funcall all 'whole)))))

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

(ert-deftest org-truss-test-board-reason-told-on-its-line ()
  "A reason stands on what it tells, on its heading's line or in its text:
its line names the member by its id as a ground, marked when it does not
hold, and draws it not besides as a member told.  A heading whose line
is the link is drawn as written, with the part the member is in beside
it.  The member's own line counts the members standing on it."
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
:TRUSS_PART: message
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
           (members (substring text (string-search " Message" text)))
           (subject (substring text 0 (string-search " Message" text))))
      (should (string-match-p "Reason[ ·]+↪Subject +- The fact$" members))
      (should (string-match-p "Reason[ ·]+↪Subject +- The bare one  ⏚bare$" members))
      (should (string-match-p "Reason[ ·]+- As the minutes have it$" members))
      (should-not (string-match-p "•" members))
      (should (string-match-p "member[ ·]+The fact$" subject))
      (should-not (string-match-p "truss-include" text))
      (goto-char (point-min))
      (search-forward "⏚bare")
      (should (eq (get-text-property (1- (point)) 'face) 'org-truss-attention)))))

(ert-deftest org-truss-test-board-foot ()
  "The foot of the board names the commands that have a key there, and
leaves the rest to be called by name."
  (org-truss-test--with-board org-truss-test--cycle-file
    (let ((text (buffer-string)))
      (should (string-match-p "^see +RET visit  TAB cycle  <backtab> cycle-all  o order  \\? guide" text))
      (should (string-match-p "^write +m source$" text))
      (should-not (string-match-p "^place" text))
      (should-not (string-match-p " new " text)))))

(ert-deftest org-truss-test-board-colours-headings-by-level ()
  "A member's heading is drawn in the face Org gives a heading of its level,
whether or not the file has been fontified, under the face of what is
outside the output document when it is; nothing else of the file's looks
-- org-indent's prefixes, say -- comes onto the board."
  (org-truss-test--with-board org-truss-test--conditions-file
    (let ((face-of (lambda (regexp label)
                     (org-truss-test--goto-line-with regexp)
                     (search-forward label (line-end-position))
                     (car (last (ensure-list (get-text-property (match-beginning 0) 'face)))))))
      (should (eq (funcall face-of (concat "member[ ·]+" org-truss-test--gap "Check with a breathalyser")
                           "Check with")
                  'org-level-2))
      (should (eq (funcall face-of (concat "member[ ·]+" org-truss-test--gap "No budget this year") "No budget")
                  'org-level-3))
      (with-current-buffer source
        (font-lock-ensure)
        (put-text-property (point-min) (point-max) 'line-prefix "  ")
        (should (equal-including-properties
                     (org-truss-member-words
                      (org-truss-member-by-words (org-truss-read) "No budget this year"))
                     "No budget this year")))
      (org-truss-board-redraw)
      (should (eq (funcall face-of (concat "member[ ·]+" org-truss-test--gap "No budget this year") "No budget")
                  'org-level-3))
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
      (org-truss-test--goto-member "Half the items repeat")
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
      (should (string-match-p "^ [△▲] (breakdown › Past, present, future, telling › Sky, Rain, Umbrella)$"
                              (buffer-string)))
      (org-truss-test--goto-line-with "^ Structure ")
      (org-truss-test--answering '("no telling")
        (org-truss-board-pattern))
      (should-not (funcall property "TRUSS_TELLING"))
      (should (string-match-p "^ [△▲] (breakdown › Past, present, future)$" (buffer-string))))))

(ert-deftest org-truss-test-board-section-gaps ()
  "A section's patterns ask the sections right below it for their roles.
s on a missing role adds a section that plays it; r on a section offers
the roles of the patterns above, those no section plays yet first."
  (org-truss-test--with-board org-truss-test--file
    (with-current-buffer source
      (org-truss-set-pattern (org-truss-test--heading-pos "Umbrella") 'breakdown '5w1h))
    (org-truss-board-redraw)
    (should (string-match-p (concat "└ Umbrella[ ·]+" org-truss-test--gap "Umbrella.*\n   △ (breakdown › 5W1H)\n")
                            (buffer-string)))
    (should (string-match-p "^     Who —$" (buffer-string)))
    (should (string-match-p (concat "^   Umbrella[ ·]+" org-truss-test--gap "Umbrella +Who, When, Where, What, Why, How$")
                            (buffer-string)))
    (org-truss-test--goto-line-with "^     When —$")
    (org-truss-test--answering '("When we start")
      (org-truss-board-new-in-structure))
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

(defun org-truss-test--parent-label (source label)
  "Return the heading LABEL sits under in SOURCE, and its level.
As (PARENT . LEVEL)."
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
                     '("Message" . 2)))
      (should (equal (plist-get (org-truss--item) :words) "Reviews start late"))
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
    (org-truss-test--goto-member "Reviews run long")
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
    (org-truss-test--goto-member "Sky")
    (org-truss-test--creating '("The team grew")
      (should (equal (org-truss-test--parent-label source "The team grew") '("Message" . 2)))
      (let ((model (org-truss-read source)))
        (should (equal (org-truss-member-id (org-truss-member-by-words model "The team grew")) "m1"))
        (should (member "m1"
                        (org-truss-member-includes
                         (car (org-truss-member-supports (org-truss-model-structure model)))))))))
  (org-truss-test--with-board org-truss-test--conditions-file
    (org-truss-test--goto-line-with "^   Future[ ·]+Constraints")
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
      (org-truss-test--goto-member "Half the items repeat")
      (org-truss-test--creating '("Most agendas match")
        (should (equal (funcall role "Most agendas match" 'logic) "reason")))
      (org-truss-test--goto-line-with "Reason \\[no grounds\\][ ·]+Some items are urgent")
      (org-truss-test--creating '("Releases cannot wait")
        (should (equal (funcall role "Releases cannot wait" 'breakdown) "part")))
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--creating '("Our review repeats itself" "Minor premise")
        (should (equal (funcall role "Our review repeats itself" 'logic) "minor")))
      (org-truss-test--goto-member "Lone remark")
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
          (org-truss-test--goto-member "Lone remark")
          (org-truss-test--answering '("Said twice")
            (org-truss-board-new))
          (with-current-buffer (org-truss-test--copy)
            (org-truss-test--let-go))
          (with-current-buffer org-truss--source
            (should-not (string-match-p "Said twice" (buffer-string))))
          (should-not (buffer-modified-p org-truss--source)))))))

(ert-deftest org-truss-test-board-marks-grounds-that-do-not-hold ()
  "A ground that does not hold is marked where the line standing on it
names it, and a source pointing to nothing says so on its line; each is
listed under its check, at the member that points to it."
  (org-truss-test--with-board (replace-regexp-in-string
                               "^# \\[\\[https://e\\.x/hallway\\]\\[hallway\\]\\]$" "# [[#lone]]\n# [[file:nowhere.pdf][the memo]]"
                               (replace-regexp-in-string "^\\*\\* Lone remark$"
                                                         "** Lone remark\n:PROPERTIES:\n:CUSTOM_ID: lone\n:END:"
                                                         org-truss-test--file))
    (let ((text (buffer-string)))
      (should (string-match-p "member[ ·]+Unused aside  ⏚lone$" text))
      (string-match "  ⏚\\(lone\\)$" text)
      (should (eq (get-text-property (1- (match-beginning 1)) 'face text) 'org-truss-dim))
      (should (eq (get-text-property (match-beginning 1) 'face text) 'org-truss-attention))
      (should (string-match-p "⏚ source \\[not found\\][ ·]+the memo" text))
      (should (string-match-p "^ Weak grounds\n   member[ ·]+Unused aside +\\[\\[#lone\\]\\] has no grounds$" text))
      (should (string-match-p "^ Broken links\n   member[ ·]+Unused aside +\\[\\[file:nowhere\\.pdf\\]\\[the memo\\]\\] not found$" text)))))

(ert-deftest org-truss-test-board-lists-claims-said-again-and-not-headings ()
  "Message's claims said again, and those not worth a heading, are listed
under their checks, after Message."
  (org-truss-test--with-board org-truss-test--claims-file
    (let ((text (buffer-string)))
      (should (string-match-p "^ Said again\n   Part[ ·]+The weekly review does not get through …  stands on \\[\\[#f1\\]\\] \\[\\[#f2\\]\\], as It drags on does\n   Part[ ·]+It drags on +stands on" text))
      (should (string-match-p "^ Not a heading\n   Part[ ·]+It drags on +used in 0 places, on 2 grounds\n   Part[ ·]+Nothing urgent waits +used in 1 place, on 1 ground$" text)))))

(ert-deftest org-truss-test-board-assumptions ()
  "A tags a member :assumption: or takes the tag off.  A reason that lacked
grounds has them then, and the board says so."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "Major premise \\[no grounds\\]")
    (org-truss-board-assume)
    (should (string-match-p "Major premise \\[assumed\\][ ·]+- A meeting" (buffer-string)))
    (org-truss-test--goto-line-with "Major premise \\[assumed\\]")
    (org-truss-board-assume)
    (should (string-match-p "Major premise \\[no grounds\\][ ·]+A meeting" (buffer-string)))))

(ert-deftest org-truss-test-board-files-a-member ()
  "f moves a member, with what is nested under it, last under a part or
another member.  Links still find it."
  (org-truss-test--with-board org-truss-test--conditions-file
    (org-truss-test--goto-member "No budget this year")
    (org-truss-test--answering '("Message")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "No budget this year") '("Message" . 2)))
    (should (equal (plist-get (org-truss--item) :words) "No budget this year"))
    (should-not (string-match-p "broken link" (buffer-string)))
    (org-truss-test--goto-member "Check with a breathalyser")
    (org-truss-test--answering '("Subject › Future: Constraints")
      (org-truss-board-refile))
    (should (equal (org-truss-test--parent-label source "Check with a breathalyser")
                   '("Constraints" . 3))))
  (org-truss-test--with-board org-truss-test--file
    (let ((model (org-truss-read source)))
      (should-not (assoc "Message › Half the items repeat › Agenda diff"
                         (org-truss--file-choices
                          model (org-truss-member-by-words model "Half the items repeat")))))
    (org-truss-test--goto-member "Half the items repeat")
    (org-truss-test--answering '("Message › Lone remark")
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
        (should (string-match-p (concat "   member[ ·]+Move to fortnightly\n"
                                        "     • included[ ·]+" org-truss-test--gap "Reviews run long")
                                text))
        (should (string-match-p "^ Broken links\n   member[ ·]+Move to fortnightly +\\[\\[truss-include:loop\\]\\] includes it back$"
                                text))
        (should (string-match-p "• broken link[ ·]+\\[\\[truss-include:gone\\]\\]" text))))
    (org-truss-test--with-board org-truss-test--includes-file
      (org-truss-test--opened-where-included)
      (should (string-match-p (concat "• included ▸2 \\[loop\\][ ·]+" org-truss-test--gap "Move to fortnightly")
                              (buffer-string))))))

(ert-deftest org-truss-test-board-numbers-sections ()
  "A section below one broken down opens with the number, the bullet or
the role the reader sees it with, as a member does."
  (org-truss-test--with-board "* M
:PROPERTIES:
:TRUSS_PART: message
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
    (should (string-match-p "├ Step[ ·]+1\\. Agree$" (buffer-string)))
    (should (string-match-p "└ Step[ ·]+2\\. Change the calendar$" (buffer-string)))))

(ert-deftest org-truss-test-board-numbers-steps ()
  "A step is drawn as one, numbered as the reader will see it."
  (org-truss-test--with-board org-truss-test--steps-file
    (let ((text (buffer-string)))
      (should (string-match-p (concat "member[ ·]+" org-truss-test--gap "Check before every test"
                                      org-truss-test--links "\n +[△▲] (breakdown › steps)")
                              text))
      (should (string-match-p (concat "Step[ ·]+" org-truss-test--gap "1\\. Meet the driver face to face$") text))
      (should (string-match-p (concat "Step \\[noexport\\][ ·]+" org-truss-test--gap "Note the reading$") text))
      (should (string-match-p (concat "Step[ ·]+" org-truss-test--gap "2\\. Breathe into the checker$") text))
      (should (string-match-p "Step[ ·]+3\\. Check the checker works$" text)))))

(ert-deftest org-truss-test-board-draws-parts ()
  "Parts are drawn by the roles they play, with the bullet, or the role, the
reader sees; a role none plays is missing, and c on one writes a member
playing it."
  (org-truss-test--with-board org-truss-test--how-file
    (let ((text (buffer-string)))
      (should (string-match-p "(breakdown › 5W1H)" text))
      ;; A compound truss's supporting members written as headings are
      ;; headings in the output document: their role, and no bullet.
      (should (string-match-p (concat "Who[ ·]+" org-truss-test--gap "Who: The driver's manager$") text))
      (should (string-match-p (concat "Step[ ·]+" org-truss-test--gap "1\\. Meet the driver$") text))
      (should (string-match-p (concat "Part[ ·]+" org-truss-test--gap "- A checker that works$") text))
      (should (string-match-p "(telling › PREP)" text))
      (should (string-match-p "What —" text)))
    (org-truss-test--goto-line-with "What —")
    (org-truss-test--creating '("Breathe into the checker")
      (should (equal (org-truss-member-roles
                      (org-truss-member-by-words (org-truss-read source) "Breathe into the checker"))
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
                      model (org-truss-member-by-words model "Read the checker"))
                     "Message › Check before every … › As follows › step 2: Read the checker"))
      (should (equal (org-truss--member-path
                      model (org-truss-member-by-words model "Someone to check"))
                     "Message › What a check needs › Part: Someone to check"))))
  (org-truss-test--with org-truss-test--conditions-file
    (let* ((model (org-truss-read))
           (names (mapcar #'car (org-truss--file-choices
                                 model (org-truss-member-by-words model "Check with a breathalyser")))))
      (should (equal (seq-drop names (seq-position names "Subject › Future: Constraints"))
                     '("Subject › Future: Constraints"
                       "Subject › Constraints › No budget this year"
                       "Subject › Constraints › The schedule is fixed"
                       "Message"))))))

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
                       reader-question-response-constraints
                       interpretation-action prep sds scqa sky-rain-umbrella)))
      (should (equal (last (funcall choices (org-truss-test--m model "Move to fortnightly")))
                     '((none . logic))))
      (should (equal (funcall choices (org-truss-model-structure model))
                     '(reasons deduction induction steps parts what-why-how pros-cons short-long past-present-future 5w1h 6w1h
                       reader-question-response-constraints
                       interpretation-action prep sds scqa sky-rain-umbrella (none . telling))))
      (should (equal (car (rassq 'prep (org-truss--pattern-choices
                                        (org-truss-test--m model "Lone remark"))))
                     "telling › PREP"))))
  (org-truss-test--with-board org-truss-test--file
    (let ((member (lambda () (org-truss-member-by-words (org-truss-read source) "Move to fortnightly"))))
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--answering '("telling › PREP")
        (org-truss-board-pattern))
      (should (eq (org-truss-member-logic (funcall member)) 'deduction))
      (should (eq (org-truss-member-telling (funcall member)) 'prep))
      (should (string-match-p "(logic › deduction, telling › PREP)" (buffer-string)))
      (should (equal (mapcar (lambda (m) (cons (org-truss-member-words m) (org-truss-member-roles m)))
                             (org-truss-member-supports (funcall member)))
                     '(("A meeting that repeats itself can meet less" (logic . major))
                       ("Point" (telling . point)) ("Reason" (telling . reason))
                       ("Example" (telling . example)) ("Point again" (telling . recap)))))
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--answering '("no telling")
        (org-truss-board-pattern))
      (should-not (org-truss-member-telling (funcall member)))
      (org-truss-test--goto-member "Move to fortnightly")
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
                    (org-truss-member-supports
                     (org-truss-member-by-words (org-truss-read source) "Check before every test"))))))
      (org-truss-test--goto-member "Check before every test")
      (org-truss-test--creating '("Thank the driver")
        (should (equal (car (last (funcall steps))) "Thank the driver"))
        (should (string-match-p (concat "Step[ ·]+" org-truss-test--gap "4\\. Thank the driver")
                                (buffer-string))))
      (org-truss-test--goto-member "Meet the driver face to face")
      (org-truss-test--creating '("The law asks to see it")
        (should (equal (org-truss-test--parent-label source "The law asks to see it")
                       '("Meet the driver face to face" . 4))))))
  (org-truss-test--with-board org-truss-test--how-file
    (org-truss-test--goto-member "Check before every test")
    (org-truss-test--creating '("A breath test" "What")
      (should (equal (org-truss-test--parent-label source "A breath test")
                     '("Check before every test" . 3)))
      (should (equal (org-truss-member-roles
                      (org-truss-member-by-words (org-truss-read source) "A breath test"))
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
            (org-truss-test--goto-member "Sky")
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
            (org-truss-test--goto-member "Lone remark")
            (org-truss-board-edit)
            (with-current-buffer (org-truss-test--copy)
              (goto-char (point-max))
              (insert "Said in passing.\n")
              (org-truss-test--let-go))
            (should-not (buffer-modified-p org-truss--source))
            (org-truss-test--goto-member "Lone remark")
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
      '(("old/truss.org" . "#+title: Old\n* Message\n:PROPERTIES:\n:TRUSS_PART: message\n:END:\n"))
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
            (org-truss-test--goto-member "Lone remark")
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
      (org-truss-test--goto-member "Reviews run long")
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
    (org-truss-test--goto-member "Sky")
    (org-truss-test--answering '("How reviews run now")
      (org-truss-board-rename))
    (should (equal (car (org-truss-test--structure-labels source)) "How reviews run now"))
    (should (string-match-p (concat "├ Sky[ ·]+" org-truss-test--gap "How reviews run now") (buffer-string)))))

(ert-deftest org-truss-test-board-edits-one-entry ()
  "e takes the line's heading out with what is under it, the headings under
it folded to their lines; the heading stays as it is in the file until the
copy is written back."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-member "Half the items repeat")
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

(ert-deftest org-truss-test-board-draws-items ()
  "Members written as items of a list are drawn as the headings under a
member are, by the roles they play, named by their targets; e on one
takes out the heading whose text holds it, at the item, and the commands
that would change a heading say so instead."
  (org-truss-test--with-board org-truss-test--items-file
    (let ((org-truss-board-fold-limit nil))
      (org-truss-board-redraw)
      (let ((text (buffer-string)))
        (should (string-match-p (concat "^   member[ ·]+" org-truss-test--marks "We move to fortnightly reviews"
                                        org-truss-test--links
                                        "\n   ▲ (logic › reasons, breakdown › Pros and cons)")
                                text))
        (should (string-match-p (concat "├ Reason · Pros[ ·]+" org-truss-test--gap "Pros: Less time in meetings"
                                        org-truss-test--links "$")
                                text))
        (should (equal (org-truss-test--id-at "^   member[ ·]+We move") "#m1"))
        (should (equal (org-truss-test--id-at "├ Reason · Pros") "<<m21>>"))
        (should (string-match-p "├ Reason · Cons \\[no grounds\\][ ·]+- Cons: Items wait longer" text))
        (should (string-match-p "│ ├ Step[ ·]+1\\. Ask the leads$" text)))
      (org-truss-test--goto-line-with "Reason · Pros")
      (let ((this-command 'org-truss-board-delete))
        (should-error (org-truss-board-delete) :type 'user-error))
      (should (string-match-p "Less time in meetings" (with-current-buffer source (buffer-string))))
      (save-window-excursion
        (let ((this-command 'org-truss-board-edit))
          (org-truss-board-edit))
        (should org-dock-mode)
        (should (string-prefix-p "** We move to fortnightly reviews" (buffer-string)))
        (should (looking-at "- pros :: <<m21>>Less time"))
        (org-truss-test--let-go)))))

(ert-deftest org-truss-test-board-draws-part-and-section-items ()
  "Members written as items in a part's text and sections in a section's
are drawn as the headings are, by the roles they play; the commands that
would change a heading say so on a section written so."
  (org-truss-test--with-board org-truss-test--part-items-file
    (let ((org-truss-board-fold-limit nil))
      (org-truss-board-redraw)
      (let ((text (buffer-string)))
        (should (string-match-p "Reader[ ·]+The team leads" text))
        (should (string-match-p "member[ ·]+We move to fortnightly reviews" text))
        (should (equal (org-truss-test--id-at "member[ ·]+We move") "<<m1>>"))
        (should (string-match-p "├ Sky[ ·]+Where we are" text)))
      (org-truss-test--goto-line-with "├ Sky")
      (let ((this-command 'org-truss-board-delete))
        (should-error (org-truss-board-delete) :type 'user-error))
      (should (string-match-p "- sky :: Where we are" (with-current-buffer source (buffer-string)))))))

(ert-deftest org-truss-test-board-catches-up ()
  "Selected again after its file changed, the board draws again."
  (org-truss-test--with-board org-truss-test--file
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (with-current-buffer source
        (goto-char (org-truss-test--heading-pos "Sky"))
        (org-edit-headline "Where we are"))
      (org-truss--catch-up (selected-window))
      (should (string-match-p (concat "├ Sky[ ·]+" org-truss-test--gap "Where we are") (buffer-string))))))

(ert-deftest org-truss-test-board-places-in-more-sections ()
  "a on a section tells there a member told elsewhere too: a member can be
told in as many places as want it, and the document tells it in each.
Told there already, nothing changes."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "└ Umbrella[ ·]+Umbrella")
    (org-truss-test--answering '("Message › Reviews run long")
      (org-truss-board-include))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-member-includes (car (org-truss-member-supports root)))
                     '("long")))
      (should (equal (org-truss-member-includes (nth 2 (org-truss-member-supports root)))
                     '("move" "none" "long"))))
    (should (= (with-temp-buffer
                 (insert (org-truss-render-document (org-truss-read source)))
                 (count-matches "^ *- Reviews run long$" (point-min) (point-max)))
               2))
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (org-truss-test--answering '("Message › Reviews run long")
      (org-truss-board-include))
    (should (equal (org-truss-member-includes
                    (car (org-truss-member-supports (org-truss-model-structure (org-truss-read source)))))
                   '("long")))))

(ert-deftest org-truss-test-board-places-an-unplaced-member ()
  "a on a section tells there the member chosen, those placed nowhere
offered first; a member placed elsewhere is placed there too, and one
placed there stays put."
  (org-truss-test--with-board org-truss-test--file
    (should (equal (mapcar #'car (seq-take (org-truss--include-choices (org-truss-read source)) 2))
                   '("Message › Unused aside" "Message › Lone remark")))
    (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
    (org-truss-test--answering '("Message › Lone remark")
      (org-truss-board-include))
    (should (equal (org-truss-member-includes
                    (car (org-truss-member-supports
                          (org-truss-model-structure (org-truss-read source)))))
                   '("long" "m1")))
    (should-not (string-match-p (concat "^ Not placed\n.*\n   member[ ·]+" org-truss-test--gap "Lone remark")
                                (buffer-string)))
    (org-truss-test--goto-member "Umbrella")
    (org-truss-test--answering '("Message › Lone remark")
      (org-truss-board-include))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-member-includes (car (org-truss-member-supports root)))
                     '("long" "m1")))
      (should (equal (org-truss-member-includes (nth 2 (org-truss-member-supports root)))
                     '("move" "none" "m1"))))
    (org-truss-test--goto-member "Umbrella")
    (org-truss-test--answering '("Message › Lone remark")
      (org-truss-board-include))
    (should (equal (org-truss-member-includes
                    (nth 2 (org-truss-member-supports
                            (org-truss-model-structure (org-truss-read source)))))
                   '("move" "none" "m1")))))

(ert-deftest org-truss-test-board-tells-in-any-heading ()
  "a on a member tells the heading chosen inside it, as on a section: a
member, or a section, which the document then tells there as it tells a
section in a list item."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-member "Move to fortnightly")
    (org-truss-test--answering '("Message › Lone remark")
      (org-truss-board-include))
    (should (equal (org-truss-member-includes
                    (org-truss-test--m (org-truss-read source) "Move to fortnightly"))
                   '("m1")))
    (org-truss-test--goto-member "Move to fortnightly")
    (org-truss-test--answering '("Structure › Sky › Sky")
      (org-truss-board-include))
    (let ((model (org-truss-read source)))
      (should (equal (org-truss-member-includes (org-truss-test--m model "Move to fortnightly"))
                     '("m1" "m2")))
      (should (equal (org-truss-member-id (car (org-truss-member-supports (org-truss-model-structure model))))
                     "m2"))
      (should (string-match-p "^- Move to fortnightly\n\n  Hold the review every other week\\.\n  - Lone remark\n  - Sky\n\n    - Reviews run long\n"
                              (org-truss-render-document model))))))

(ert-deftest org-truss-test-board-links-to-sections ()
  "A section is a heading like any other to the links that reach it: b
offers it as a ground, and = goes from the line standing on it to where
it is written, lit together."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-member "Move to fortnightly")
    (org-truss-test--answering '("Structure › Sky › Sky")
      (org-truss-board-ground))
    (let ((model (org-truss-read source)))
      (should (equal (org-truss-member-grounds (org-truss-test--m model "Move to fortnightly"))
                     '("half" "m1")))
      (should (equal (org-truss-member-id (car (org-truss-member-supports (org-truss-model-structure model))))
                     "m1")))
    ;; A section holds as any heading does: with no grounds of its own, it
    ;; is a weak ground.
    (should (string-match-p "member[ ·]+Move to fortnightly  ⏚m1$" (buffer-string)))
    (org-truss-test--goto-line-with "member[ ·]+Move to fortnightly  ⏚m1$")
    (search-forward "⏚m1")
    (should (eq (get-text-property (1- (point)) 'face) 'org-truss-attention))
    (cl-loop repeat 4 until (looking-at " ├ Sky") do (org-truss-board-same))
    (should (looking-at " ├ Sky"))
    (should (seq-some (lambda (o) (eq (overlay-get o 'face) 'org-truss-same))
                      (overlays-in (point-min) (point-max))))))

(ert-deftest org-truss-test-board-places-instead-of-a-broken-link ()
  "a on a broken link places the chosen member where the link stands; where
else it is placed, it stays."
  (org-truss-test--with-board org-truss-test--file
    (let ((links (lambda (n) (org-truss-member-includes
                              (nth n (org-truss-member-supports
                                      (org-truss-model-structure (org-truss-read source))))))))
      (org-truss-test--goto-line-with "broken link[ ·]+\\[\\[truss-include:none\\]\\]")
      (org-truss-test--answering '("Message › Lone remark")
        (org-truss-board-include))
      (should (equal (funcall links 2) '("move" "m1")))
      (should-not (string-match-p "broken link" (buffer-string))))
    ;; A link that names a heading is broken too, and is put right the same way.
    (with-current-buffer source
      (goto-char (point-max))
      (insert "- [[truss-include:*Reviews run long]]\n- [[truss-include:last]]\n"))
    (org-truss-board-redraw)
    (org-truss-test--goto-line-with "broken link[ ·]+\\[\\[truss-include:\\*Reviews run long\\]\\]")
    (org-truss-test--answering '("Message › Reviews run long")
      (org-truss-board-include))
    (let ((root (org-truss-model-structure (org-truss-read source))))
      (should (equal (org-truss-member-includes (car (org-truss-member-supports root)))
                     '("long")))
      (should (equal (org-truss-member-includes (nth 2 (org-truss-member-supports root)))
                     '("move" "m1" "long" "last"))))))

(ert-deftest org-truss-test-board-takes-out-and-deletes ()
  "d takes a member out of the structure and leaves it in the file; D deletes
it from the file, with what is under it and what placed it, leaving the
grounds that named it to show as broken."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-structure-member "Reviews run long")
    (org-truss-board-take-out)
    (let ((model (org-truss-read source)))
      (should (org-truss-member-by-words model "Reviews run long"))
      (should (null (org-truss-member-includes
                     (car (org-truss-member-supports (org-truss-model-structure model)))))))
    (org-truss-test--goto-member "Half the items repeat")
    (org-truss-test--answering '(nil)
      (org-truss-board-delete))
    (should (org-truss-member-by-words (org-truss-read source) "Half the items repeat"))
    (org-truss-test--goto-member "Half the items repeat")
    (org-truss-test--answering '(t)
      (org-truss-board-delete))
    (let ((model (org-truss-read source)))
      (should-not (org-truss-member-by-words model "Half the items repeat"))
      (should-not (org-truss-member-by-words model "Agenda diff"))
      (should (null (org-truss-member-includes
                     (nth 1 (org-truss-member-supports (org-truss-model-structure model))))))
      (should (equal (org-truss-member-grounds (org-truss-member-by-words model "Move to fortnightly"))
                     '("half"))))
    (should (string-match-p "Move to fortnightly  ⏚half$" (buffer-string)))
    (goto-char (point-min))
    (search-forward "⏚half")
    (should (eq (get-text-property (1- (point)) 'face) 'org-truss-attention))
    (should (string-match-p (concat "^ Broken links\n +member[ ·]+" org-truss-test--gap
                                    "Move to fortnightly +\\[\\[#half\\]\\] not found$")
                            (buffer-string)))))

(ert-deftest org-truss-test-board-grounds ()
  "b makes another member a ground, or no longer one, and the member's line
names one it cannot stand on."
  (org-truss-test--with-board org-truss-test--file
    (let ((grounds (lambda () (org-truss-member-grounds
                               (org-truss-member-by-words (org-truss-read source) "Move to fortnightly")))))
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--answering '("Message › Unused aside")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("half" "aside")))
      (should (string-match-p "member[ ·]+Move to fortnightly$" (buffer-string)))
      ;; A member pointed to for the first time is given an id.
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--answering '("Message › Lone remark")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("half" "aside" "m1")))
      (should (with-current-buffer source
                (string-match-p "^Hold the review every other week\\.\n# \\[\\[#aside\\]\\]\n# \\[\\[#m1\\]\\]\n"
                                (buffer-string))))
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--answering '("Message › Lone remark")
        (org-truss-board-ground))
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--answering '("Message › Half the items repeat")
        (org-truss-board-ground))
      (should (equal (funcall grounds) '("aside")))
      (org-truss-test--goto-member "Move to fortnightly")
      (org-truss-test--answering '("Message › Unused aside")
        (org-truss-board-ground))
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
      (org-truss-board-new-in-structure))
    (should (equal (org-truss-test--structure-labels source) '("Sky" "Rain" "More rain" "Umbrella")))
    (should-not (string-match-p "Out of order" (buffer-string)))
    (org-truss-test--goto-line-with "├ Rain[ ·]+More rain")
    (org-truss-test--answering '("Umbrella")
      (org-truss-board-roles))
    (should (equal (org-truss-member-roles
                    (nth 2 (org-truss-member-supports
                            (org-truss-model-structure (org-truss-read source)))))
                   '((telling . umbrella))))))

(ert-deftest org-truss-test-board-keeps-up-with-the-file ()
  "A hand edit to the file is drawn before the next command, which then acts
at once.  Fontifying the file is not an edit.  Only an edit made while a
command is asking makes it draw again instead of acting."
  (org-truss-test--with-board org-truss-test--file
    (let ((umbrella (lambda () (org-truss-member-includes
                                (nth 2 (org-truss-member-supports
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
      (org-truss-test--answering '("Message › Reviews run long")
        (org-truss-board-include))
      (should (member "long" (funcall umbrella)))
      (org-truss-test--goto-line-with "├ Sky[ ·]+Sky")
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (&rest _)
                   (with-current-buffer source
                     (goto-char (point-min))
                     (insert "\n"))
                   "Message › Lone remark")))
        (should-error (org-truss-board-include) :type 'user-error))
      (should (member "long" (funcall umbrella))))))

(ert-deftest org-truss-test-board-orders-headings ()
  "M-down moves a section after its next sibling, and a member where it is
written after its next one, with what is nested under it: an order the
telling pattern does not want is put right from the board."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-member "Sky")
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
                    (org-truss-member-supports
                     (org-truss-member-by-words (org-truss-read source) "We move to fortnightly reviews")))
                   '("Reviews are weekly" "Half the items repeat" "Should we keep meeting weekly"
                     "Robin agrees")))
    (should-not (string-match-p "Out of order" (buffer-string)))))

(ert-deftest org-truss-test-board-refiles-a-section ()
  "f moves a section, with what is under it, last under another section; it
cannot go under itself, and the structure stays where it is."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-member "Sky")
    (org-truss-test--answering '("Structure › Umbrella › Umbrella")
      (org-truss-board-refile))
    (should (equal (org-truss-test--structure-labels source) '("Rain" "Umbrella")))
    (should (equal (org-truss-test--parent-label source "Sky") '("Umbrella" . 3)))
    (should (string-match-p (concat "• included[ ·]+" org-truss-test--gap "Reviews run long") (buffer-string)))
    (org-truss-test--goto-line-with "^ Structure ")
    (should-error (org-truss-board-refile) :type 'user-error)))

(ert-deftest org-truss-test-board-draws-the-parts-in-order ()
  "The subject, the members and the structure each take a part of the board,
in the order the work is done, each followed by what is left to do there.
A part's members are drawn as any member is.  Everywhere a member's right
is what the document tells of it, after it what it stands on and how many
use it."
  (org-truss-test--with-board org-truss-test--clusters-file
    (let ((text (buffer-string)))
      (should (string-match-p
               (concat "^ Subject .*\n"
                       " △ (breakdown › Past, present, future)\n"
                       "   Past[ ·]+Premises\n"
                       "   └ member[ ·]+How many cars we run\n"
                       "   Future[ ·]+Constraints\n"
                       "   ├ member[ ·]+The manager checks every driver before and after driving\n"
                       "   │ △ (logic › reasons)\n"
                       "   │ ├ Reason[ ·]+- The rule asks for a check before driving\n")
               text))
      (should (string-match-p (concat "member[ ·]+A manager is named.*\n"
                                      "   │   ⏚ source[ ·]+law 74-3\n"
                                      "   └ member[ ·]+The law binds us, so we must check\n")
                              text))
      (should (< (string-match "^ Subject " text) (string-match "^ Message " text)
                 (string-match "^ Structure " text)))
      (should (string-match-p (concat "├ Situation[ ·]+" org-truss-test--gap "Background\n"
                                      " │   • included ▸3[ ·]+" org-truss-test--gap "The manager checks every driver before and after driving\n"
                                      " └ Answer")
                              text))
      (should (string-match-p (concat "Step[ ·]+" org-truss-test--gap "1\\. The driver blows into the tester") text)))))

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
    (org-truss-test--goto-member "The manager checks")
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
      (should (string-match-p (concat "^ ├ Sky ⚠[ ·]+" org-truss-test--gap "空$") text))
      (should (equal (get-text-property (string-match "^ ├ Sky ⚠" text) 'help-echo text)
                     "Sky, Rain, Umbrella tells it before Rain, which is above it in the file"))
      (should (string-match-p (concat "^ Out of order\n   Sky[ ·]+" org-truss-test--gap "空 +below Rain$") text))
      (should (string-match-p "^ └ member \\[no role\\][ ·]+Notes for later" text))
      (should (eq (get-text-property (string-match "\\[no role\\][ ·]+Notes for later" text) 'face text)
                  'org-truss-attention))
      (should (string-match-p "^ No role\n   member \\[no role\\][ ·]+Notes for later +plays no role of telling › Sky, Rain, Umbrella$"
                              text))
      (should (string-match-p "└ member \\[no role\\][ ·]+Example$" text))
      (should (string-match-p "^ No role\n   member \\[no role\\][ ·]+Example +plays no role of telling › PREP$"
                              text)))))

(ert-deftest org-truss-test-board-tells-aspects-of-reasons ()
  "In the structure a reason playing a role of a breakdown opens with it,
as the reader is told it: in the breakdown's list."
  (org-truss-test--with-board "* M
:PROPERTIES:
:TRUSS_PART: message
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
    (org-truss-test--goto-structure-line-with "Less time in meetings")
    (should (string-match-p "[ ·]- Pros: Less time in meetings$"
                            (buffer-substring (point) (line-end-position))))))

(ert-deftest org-truss-test-board-opens-members-where-told ()
  "O opens the members a section lists under it, with their sources, gaps
and the members they stand on, in turn, and leaves them out where they
are written; O again opens them where written and lists them on one line
in the structure.  Point stays on the member, where it is opened.  The
mode line says which."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-member "Half the items repeat")
    (org-truss-board-fold)
    (org-truss-board-order)
    (should (equal mode-name "Truss included"))
    (should (looking-at (concat " │   • included[ ·]+" org-truss-test--gap "Half the items repeat")))
    (should-not (string-match-p "^   member[ ·]+Half the items repeat$" (buffer-string)))
    ;; Drawn in full the first time, the original, it says how many ghosts
    ;; it has; each ghost, under which member of Structure the original is.
    (should (string-match-p "• included[ ·]+\\+1 - Half the items repeat$" (buffer-string)))
    (should (string-match-p "⏚ reason ▸6[ ·]+◌Rain Half the items repeat$" (buffer-string)))
    (should (string-match-p "^   member[ ·]+Lone remark$" (buffer-string)))
    (should (string-match-p (concat "^ └ Umbrella.*\n"
                                    "     • included[ ·]+" org-truss-test--gap "Move to fortnightly\n"
                                    "     △ (logic › deduction)\n"
                                    "     │ ⏚ reason ▸6[ ·]+" org-truss-test--marks "Half the items repeat\n"
                                    "     └ Major premise \\[no grounds\\].*\n"
                                    "       Minor premise —\n")
                            (buffer-string)))
    (org-truss-board-order)
    (should (equal mode-name "Truss"))
    (should (looking-at "   member[ ·]+Half the items repeat"))
    (should (string-match-p "^ │   • included ▸5[ ·]+- Half the items repeat" (buffer-string))))
  (org-truss-test--with-board org-truss-test--clusters-file
    (org-truss-test--opened-where-included)
    (should-not (string-match-p "^   [├└] member[ ·]+The manager checks" (buffer-string)))
    (should (string-match-p (concat "^ │   • included[ ·]+" org-truss-test--gap
                                    "The manager checks every driver.*\n │   △ (logic › reasons)\n")
                            (buffer-string)))
    ;; What a member stands on follows it, and what that stands on, down
    ;; to the sources; drawn before, it is one line, folded.
    (should (string-match-p (concat "     │ ⏚ reason[ ·]+" org-truss-test--marks "The rule may apply to us\n"
                                    "     │   ⏚ reason[ ·]+" org-truss-test--marks "A manager is named for five cars or more\n"
                                    "     │     ⏚ source[ ·]+law 74-3\n"
                                    "     │ ⏚ reason ▸3[ ·]+" org-truss-test--marks "The manager checks")
                            (buffer-string)))))

(ert-deftest org-truss-test-board-tells-where-it-is-written ()
  "Where a member is written, its words are what the document tells of it:
its steps numbered, its aspects labelled; in the face of what is not
told while nothing tells it; words too long for the middle are cut
short."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "^   member[ ·]+Reviews run long\n" text))
      (should (string-match-p "Major premise \\[no grounds\\][ ·]*- A meeting that repeats itself can meet less$"
                              text))
      (org-truss-test--goto-line-with "^   member[ ·]+\\(Lone remark\\)$")
      (should (eq (car-safe (get-text-property (match-beginning 1) 'face)) 'org-truss-outside))
      (org-truss-test--goto-line-with "^   member[ ·]+\\(Reviews run long\\)$")
      (should-not (eq (car-safe (get-text-property (match-beginning 1) 'face)) 'org-truss-outside))))
  (let ((org-truss-board-middle-width 24))
    (org-truss-test--with-board org-truss-test--clusters-file
      (should (string-match-p "member[ ·]+Drivers are checked bef…$" (buffer-string)))
      (should (string-match-p "Step[ ·]+1\\. The driver blows int…$"
                              (org-truss-test--top))))))

(ert-deftest org-truss-test-board-names-members-by-id ()
  "A member is named by its CUSTOM_ID where the mouse is on the dots of its
line: #m where it is written, and [[#m]] where a link includes it.
Nested under a member a section calls, a member is not called itself,
and is named by nothing; one with no id, by nothing anywhere.  The
dots run up to the words, which start in the same column all the same."
  (org-truss-test--with-board org-truss-test--file
    (let ((text (buffer-string)))
      (should (string-match-p "^   member ·+ Half the items repeat$" text))
      (should (equal (org-truss-test--id-at "^   member ·+ Half the items repeat$") "#half"))
      (should (string-match-p "^ │   • included ▸5 ·+ - Half the items repeat$" text))
      (should (equal (org-truss-test--id-at "^ │   • included ▸5 ·+ - Half") "[[#half]]"))
      (should (string-match-p "^   member ·+ Lone remark$" text))
      (should-not (org-truss-test--id-at "^   member ·+ Lone remark$"))
      (should (= (org-truss-test--column-of "^   member ·+ Half" "Half the items repeat")
                 (org-truss-test--column-of "^   member ·+ Lone remark" "Lone remark"))))
    (org-truss-test--opened-where-included)
    (let ((text (buffer-string)))
      (should (string-match-p (concat "^ │   • included ·+ " org-truss-test--gap "Half the items repeat$") text))
      (should (string-match-p "^ │   ├ Reason \\[noexport\\][ ·]+Agenda diff$" text))
      (should-not (org-truss-test--id-at "^ │   ├ Reason \\[noexport\\]")))))

(ert-deftest org-truss-test-board-goes-to-the-same-member ()
  "= on a line including a member goes to where it is drawn in full; there,
to the lines linked to it one step either way, in turn, and round.
Opened where included, a member is drawn in full where Structure's links
first bring it."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-line-with "^ Structure ")
    (org-truss-test--goto-line-with "included ▸5 ·+ - Half the items repeat" (point))
    (org-truss-board-same)
    (should (looking-at "   member ·+ Half the items repeat"))
    ;; What it stands on, then what stands on it or includes it, in the
    ;; board's order, and round.
    (let ((seen nil))
      (dotimes (_ 6)
        (org-truss-board-same)
        (push (buffer-substring (point) (line-end-position)) seen))
      (setq seen (nreverse seen))
      (should (string-match-p "member ·+ Reviews run long" (nth 0 seen)))
      (should (string-match-p "Reason \\[noexport\\] ·+ Agenda diff$" (nth 1 seen)))
      (should (string-match-p "member ·+ Move to fortnightly$" (nth 2 seen)))
      (should (string-match-p "included ▸5 ·+ - Half the items repeat" (nth 3 seen)))
      (should (string-match-p (concat "included ▸1 ·+ " org-truss-test--gap "Move to fortnightly$") (nth 4 seen)))
      (should (equal (nth 5 seen) (nth 0 seen)))))
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-structure-line-with "⏚ reason ▸6 ·+ ◌[^ ]* Half the items repeat")
    (org-truss-board-same)
    (should (looking-at (concat " │   • included ·+ " org-truss-test--gap "Half the items repeat")))
    (let ((seen nil))
      (dotimes (_ 5)
        (org-truss-board-same)
        (push (buffer-substring (point) (line-end-position)) seen))
      (setq seen (nreverse seen))
      (should (string-match-p (concat "included ·+ " org-truss-test--gap "Reviews run long") (nth 0 seen)))
      (should (string-match-p "Reason \\[noexport\\][ ·]+Agenda diff" (nth 1 seen)))
      (should (string-match-p (concat "included ·+ " org-truss-test--gap "Move to fortnightly") (nth 2 seen)))
      (should (string-match-p "⏚ reason ▸6 ·+ ◌[^ ]* Half the items repeat" (nth 3 seen)))
      (should (equal (nth 4 seen) (nth 0 seen))))))

(ert-deftest org-truss-test-board-unfolds-to-the-same-member ()
  "= unfolds a member that hides where the member is written."
  (let ((org-truss-board-fold-limit 1))
    (org-truss-test--with-board org-truss-test--conditions-file
      (should-not (string-match-p "member[ ·]+No budget" (buffer-string)))
      (org-truss-test--goto-line-with "^ Structure ")
      (org-truss-test--goto-member "No budget this year" (point))
      (org-truss-board-same)
      (should (looking-at "   ├ member ·+ No budget this year")))))

(ert-deftest org-truss-test-board-lights-the-same-member ()
  "The lines naming the member on the line at point are lit, but that line:
where it is drawn again, the lines it takes below its own; and the lines
linked to it one step either way, where what it stands on is drawn in
full and the lines standing on it."
  (org-truss-test--with-board org-truss-test--file
    (org-truss-test--goto-structure-member "Half the items repeat")
    (org-truss--light-same)
    (let ((lit (mapcar (lambda (overlay)
                         (buffer-substring (overlay-start overlay) (1- (overlay-end overlay))))
                       org-truss--same-overlays)))
      (should (seq-some (lambda (line) (string-match-p "⏚ reason ▸6 ·+ ◌[^ ]* Half the items repeat" line)) lit))
      (should (seq-some (lambda (line) (string-match-p (concat "included ·+ " org-truss-test--gap "Move to fortnightly") line)) lit))
      (should (seq-some (lambda (line) (string-match-p (concat "included ·+ " org-truss-test--gap "Reviews run long") line)) lit))
      (should-not (seq-some (lambda (line) (string-match-p "Lone remark" line)) lit))
      (should-not (seq-some (lambda (line) (string-match-p "^ │   • included[ ·]+[^\n]*Half the items" line)) lit)))
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
        (org-truss-test--goto-member "New approval rules")
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
          (should (equal (org-with-point-at (org-truss--alone-here) (org-get-heading t t t t))
                         "New approval rules")))))))

(ert-deftest org-truss-test-agent-told-the-patterns ()
  "A heading taken out with patterns tells an agent their roles, as the
values of the role properties and the words of the members put in for
them, how one is written, and which must have grounds."
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
              (should (string-match-p "words one sentence that states what plays the role" text))
              (should (string-match-p "In a TRUSS_LOGIC truss, give each supporting member grounds" text)))))))))

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
                  (concat "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_PART: message\n:END:\n"
                          org-truss-test--steps))
            (cons "project.org" (concat "* Tasks\n" org-truss-test--steps "* Log\n")))
    (let ((truss (org-truss-test--request-of (expand-file-name "doc/truss.org" dir) "First step"))
          (project (org-truss-test--request-of (expand-file-name "project.org" dir) "First step")))
      (dolist (text (list truss project))
        (should (string-match-p "^- steps (TRUSS_BREAKDOWN): .*\n  Roles: step \\[Step\\]$" text))
        (should (string-match-p "plays step in the steps of \"Procedure\", above the copy" text))
        (should (string-match-p "-f org-truss-batch-check [^ ]*First-step\\.org$" text)))
      (should (string-match-p "rules of the file are in its guide" truss))
      (should-not (string-match-p "in its guide" project))
      (should-not (string-match-p "## Truss"
                                  (org-truss-test--request-of (expand-file-name "project.org" dir) "Log"))))))

(ert-deftest org-truss-test-check-copy ()
  "A copy is checked written back where it came from: what is in it by its
own lines, and outside it only what it brings about, by the file's lines
as they are."
  (org-truss-test--in-directory
      (list (cons "truss.org"
                  (concat "#+title: T\n* Message\n:PROPERTIES:\n:TRUSS_PART: message\n:END:\n"
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

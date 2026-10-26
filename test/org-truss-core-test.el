;;; org-truss-core-test.el --- Tests for org-truss-core, -edit and -guide  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -L ../org-dock -l test/org-truss-core-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss-core)
(require 'org-truss-edit)
(require 'org-truss-guide)

(defconst org-truss-test--file "#+title: Fortnightly reviews

* Brief
:PROPERTIES:
:TRUSS_PART: brief
:TRUSS_BREAKDOWN: reader-question-response-constraints
:END:
** Reader
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: reader
:END:
:GUIDE:
Who reads it.
:END:
The team leads.

* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** Reviews run long
:PROPERTIES:
:CUSTOM_ID: long
:END:
# [[https://e.x/calendar-export][calendar export]]
Reviews ran past the hour eight times this quarter.

** Half the items repeat
:PROPERTIES:
:CUSTOM_ID: half
:TRUSS_LOGIC: reasons
:END:
# [[#long]]
# Robin keeps raising the same items; see [[#diff]].
Half of each agenda repeats the week before, as [[#long]] shows.
*** Agenda diff                                                  :noexport:
:PROPERTIES:
:CUSTOM_ID: diff
:TRUSS_LOGIC_ROLE: reason
:END:
# [[https://e.x/agendas-weeks-1-12][agendas, weeks 1-12]]
*** Items need a week to move                                    :assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
We assume most items need more than a week to change.
*** Some items are urgent
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_BREAKDOWN: parts
:END:
Some items cannot wait two weeks.
**** Urgent items go to chat
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: part
:END:
# [[https://e.x/team-agreement][team agreement]]
**** Who decides what is urgent
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: part
:END:

** Move to fortnightly
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_LOGIC: deduction
:END:
# [[#half]]
Hold the review every other week.
*** A meeting that repeats itself can meet less
:PROPERTIES:
:TRUSS_LOGIC_ROLE: major
:END:

** Unused aside
:PROPERTIES:
:CUSTOM_ID: aside
:END:
# [[https://e.x/hallway][hallway]]

** Lone remark

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_TELLING: sky-rain-umbrella
:END:
** Sky
:PROPERTIES:
:TRUSS_TELLING_ROLE: sky
:END:
- [[truss-include:long]]

** Rain
:PROPERTIES:
:TRUSS_TELLING_ROLE: rain
:END:
- [[truss-include:half]]

** Umbrella
:PROPERTIES:
:TRUSS_TELLING_ROLE: umbrella
:END:
- [[truss-include:move]]
- [[truss-include:none]]
"
  "A truss file with grounds of each kind, reasons lacking them, a breakdown
and a structure with a broken link.")

(defconst org-truss-test--conditions-file "#+title: Checks before a test

* Brief
:PROPERTIES:
:TRUSS_PART: brief
:TRUSS_BREAKDOWN: reader-question-response-constraints
:END:
** Reader
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: reader
:END:
The safety board.
** Their question
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: question
:END:
** Response wanted
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: response
:END:

* Subject
:PROPERTIES:
:TRUSS_PART: subject
:TRUSS_BREAKDOWN: past-present-future
:END:
** Issue
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: present
:END:
*** Nobody checks before a test
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: future
:END:
Finance said so at the October meeting.
*** No budget this year
:PROPERTIES:
:CUSTOM_ID: budget
:END:
# [[https://e.x/finance-3-october][finance, 3 October]]
*** The schedule is fixed

* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** Check with a breathalyser

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Constraints
- [[truss-include:budget]]
"
  "A truss file with members written under fields of the subject.")

(defconst org-truss-test--clusters-file "#+title: Checks before a test

* Brief
:PROPERTIES:
:TRUSS_PART: brief
:END:

* Subject
:PROPERTIES:
:TRUSS_PART: subject
:TRUSS_BREAKDOWN: past-present-future
:END:
** Premises
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: past
:END:
*** How many cars we run
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: future
:END:
*** The manager checks every driver before and after driving
:PROPERTIES:
:CUSTOM_ID: rule
:TRUSS_LOGIC: reasons
:END:
The rules ask for a check before and after driving.
**** The rule asks for a check before driving
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
# [[https://e.x/rule-6][rule 6]]
**** The rule asks for a check after driving
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
# [[https://e.x/rule-6][rule 6]]
**** The check may be made by video
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
# [[https://e.x/notice-2-2][notice 2(2)]]
*** A manager is named for five cars or more
:PROPERTIES:
:CUSTOM_ID: five
:END:
# [[https://e.x/law-74-3][law 74-3]]
*** The law binds us, so we must check
:PROPERTIES:
:END:
# [[#five]]

* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** The rule may apply to us
:PROPERTIES:
:CUSTOM_ID: may
:END:
# [[#five]]
** Drivers are checked before and after driving
:PROPERTIES:
:CUSTOM_ID: checked
:TRUSS_BREAKDOWN: steps
:END:
# [[#may]]
# [[#rule]]
*** The driver blows into the tester
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
*** The manager reads it
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
** The tester reads zero when sober
:PROPERTIES:
:END:
# [[https://e.x/tester-manual][tester manual]]

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_TELLING: scqa
:END:
** Background
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
- [[truss-include:rule]]
** What we do
:PROPERTIES:
:TRUSS_TELLING_ROLE: answer
:END:
- [[truss-include:checked]]
"
  "A truss file whose subject holds facts summed up under the one they are
the reasons of, and whose members hold steps.")

(defconst org-truss-test--steps-file "#+title: Checks before a test

* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** The law asks for a check
:PROPERTIES:
:CUSTOM_ID: law
:END:
# [[https://e.x/ordinance-article-9-10][ordinance, article 9-10]]
** Check before every test
:PROPERTIES:
:CUSTOM_ID: check
:TRUSS_BREAKDOWN: steps
:END:
# [[#law]]
*** Meet the driver face to face
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
**** A video call counts as face to face
:PROPERTIES:
:END:
# [[https://e.x/notice-2022][notice, 2022]]
*** Note the reading                                              :noexport:
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
*** Breathe into the checker
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
The driver breathes into the checker.
*** Check the checker works
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
** Steps with nothing behind them
:PROPERTIES:
:TRUSS_BREAKDOWN: steps
:END:
*** The only step
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Do
:PROPERTIES:
:TRUSS_TELLING_ROLE: conclusion
:END:
- [[truss-include:check]]
"
  "A truss file with a member broken down into steps.")

(defconst org-truss-test--how-file "#+title: Checks before a test

* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** Check before every test
:PROPERTIES:
:CUSTOM_ID: check
:TRUSS_BREAKDOWN: 5w1h
:END:
*** The driver's manager
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: who
:END:
*** In the office or by video call
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: where
:END:
*** Before the first run of the day
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: when
:END:
*** As follows
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: how
:TRUSS_BREAKDOWN: steps
:END:
**** Meet the driver
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
**** Read the checker
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
** What a check needs
:PROPERTIES:
:CUSTOM_ID: needs
:TRUSS_BREAKDOWN: parts
:END:
*** A checker that works
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: part
:END:
*** Someone to check
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: part
:END:
** Tests are safer checked
:PROPERTIES:
:CUSTOM_ID: safer
:TRUSS_TELLING: prep
:END:
*** A drunk driver crashed last year
:PROPERTIES:
:TRUSS_TELLING_ROLE: example
:END:
# [[https://e.x/incident-log][incident log]]
*** Alcohol slows reactions
:PROPERTIES:
:TRUSS_TELLING_ROLE: reason
:END:
# [[https://e.x/textbook][textbook]]

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Do
- [[truss-include:check]]
- [[truss-include:needs]]
- [[truss-include:safer]]
"
  "A truss file with a 5W1H breakdown holding steps, parts, and a PREP.")

(defconst org-truss-test--unfinished-file "#+title: T
* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** Move to fortnightly
:PROPERTIES:
:CUSTOM_ID: m1
:TRUSS_TELLING: prep
:END:
*** Reason
:PROPERTIES:
:TRUSS_TELLING_ROLE: reason
:END:
*** 理由は会議が短くなること
:PROPERTIES:
:TRUSS_TELLING_ROLE: reason
:END:
*** Example
** Example
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_TELLING: sky-rain-umbrella
:END:
** Rain
:PROPERTIES:
:TRUSS_TELLING_ROLE: rain
:END:
- [[truss-include:m1]]
** 空
:PROPERTIES:
:TRUSS_TELLING_ROLE: sky
:END:
** Umbrella
:PROPERTIES:
:TRUSS_TELLING_ROLE: umbrella
:END:
Meet every other week.
** Notes for later
"
  "A file part written: a heading playing no role, sections out of order.")

(defconst org-truss-test--telling-text "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** We move to fortnightly reviews
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_TELLING: scqa
:END:
From next month.
*** Should we keep meeting weekly
:PROPERTIES:
:TRUSS_TELLING_ROLE: question
:END:
*** Half the items repeat
:PROPERTIES:
:TRUSS_TELLING_ROLE: complication
:END:
*** Robin agrees
*** Reviews are weekly
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[truss-include:move]]
"
  "A member told by SCQA, what is under it written out of the pattern's order.")

(defmacro org-truss-test--with (text &rest body)
  "Run BODY in an Org buffer holding TEXT."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (org-mode)
     (goto-char (point-min))
     ,@body))

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
                   (string-prefix-p "*truss " (buffer-name buffer))
                   (and (boundp 'org-dock--session)
                        (buffer-local-value 'org-dock--session buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory dir t))))

(defun org-truss-test--labels (members)
  (mapcar #'org-truss-member-words members))

(defun org-truss-test--m (model label)
  (or (org-truss-member-by-words model label)
      (error "No member %s" label)))

(defun org-truss-test--heading-pos (label)
  "Return the position of the first heading labelled LABEL."
  (save-excursion
    (goto-char (point-min))
    (catch 'found
      (while (re-search-forward org-heading-regexp nil t)
        (when (equal (org-get-heading t t t t) label)
          (throw 'found (line-beginning-position))))
      (error "No heading %s" label))))

(defun org-truss-test--section-labels (section)
  (mapcar #'org-truss-member-words (org-truss-member-supports section)))

(defun org-truss-test--cluster-labels (clusters)
  (mapcar #'org-truss-member-words clusters))

;;;; Patterns and roles

(ert-deftest org-truss-test-roles-by-kind ()
  "A heading plays a role in each pattern of the heading above, each in the
property of its kind.  A pattern asks for its roles of what is right under
it, and lacks those none plays: a breakdown of 5W1H its aspects, a telling
pattern its places, PREP's point and its point again too.  What fills a
telling pattern's places is told in the order of the file, and what comes
below one the pattern tells after it is out of order."
  (org-truss-test--with org-truss-test--how-file
    (let* ((model (org-truss-read))
           (check (org-truss-test--m model "Check before every test"))
           (follows (org-truss-test--m model "As follows"))
           (safer (org-truss-test--m model "Tests are safer checked")))
      (should (equal (org-truss-member-roles follows) '((breakdown . how))))
      (should (eq (org-truss-member-role follows 'breakdown) 'how))
      (should (eq (org-truss-member-breakdown follows) 'steps))
      (should (equal (org-truss-gaps check) '((breakdown what . 1) (breakdown why . 1))))
      (should-not (org-truss-gaps follows))
      (should (equal (org-truss-supporting-role-ids safer 'telling) '(point reason example recap)))
      (should (equal (org-truss-gaps safer) '((telling point . 1) (telling recap . 1))))
      (should-not (org-truss-no-role check))
      (should (equal (mapcar (lambda (o) (cons (org-truss-member-words (car o))
                                               (org-truss-member-words (cdr o))))
                             (plist-get (org-truss-checks model) :out-of-order))
                     '(("Alcohol slows reactions" . "A drunk driver crashed last year"))))))
  (org-truss-test--with (replace-regexp-in-string
                         ":TRUSS_TELLING: prep" ":TRUSS_LOGIC: deduction\n:TRUSS_TELLING: prep"
                         org-truss-test--how-file)
    (let ((member (org-truss-test--m (org-truss-read) "Tests are safer checked")))
      (should (equal (org-truss-gaps member) '((logic major . 1) (logic minor . 1)
                                               (telling point . 1) (telling recap . 1))))
      (should (equal (mapcar (lambda (hit) (cons (org-truss-member-words (car hit)) (cdr hit)))
                             (org-truss-no-role member))
                     '(("A drunk driver crashed last year" . logic)
                       ("Alcohol slows reactions" . logic)))))))

(ert-deftest org-truss-test-induction-wants-two-cases ()
  "A role a pattern wants more of is short by as many as are missing."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** General
:PROPERTIES:
:TRUSS_LOGIC: induction
:END:
*** One
:PROPERTIES:
:TRUSS_LOGIC_ROLE: case
:END:
[[https://e.x/x][x]]
"
    (should (equal (org-truss-gaps (org-truss-test--m (org-truss-read) "General"))
                   '((logic case . 1))))))

(ert-deftest org-truss-test-no-role ()
  "A heading right under one with a pattern plays a role of it, or plays
none: its role property for that kind is missing, or names no role of the
pattern.  A telling pattern with a place for anything leaves none out.
Two roles in one pattern's property are none of its roles."
  (org-truss-test--with org-truss-test--unfinished-file
    (let* ((model (org-truss-read))
           (hits (plist-get (org-truss-checks model) :no-role)))
      (should (equal (mapcar (lambda (hit) (list (org-truss-member-words (car hit)) (cadr hit)
                                                 (org-truss-member-words (cddr hit))))
                             hits)
                     '(("Example" telling "Move to fortnightly")
                       ("Notes for later" telling "Structure"))))))
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Told as SDS
:PROPERTIES:
:TRUSS_TELLING: sds
:END:
*** Anything
** Broken down
:PROPERTIES:
:TRUSS_BREAKDOWN: pros-cons
:END:
*** For
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: pros
:END:
*** Both
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: pros cons
:END:
*** Elsewhere
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: who
:END:
"
    (let ((model (org-truss-read)))
      (should-not (org-truss-no-role (org-truss-test--m model "Told as SDS")))
      (should (equal (org-truss-test--labels
                      (mapcar #'car (org-truss-no-role (org-truss-test--m model "Broken down"))))
                     '("Both" "Elsewhere"))))))

(ert-deftest org-truss-test-no-pattern ()
  "A heading that says a role of a kind the heading above has no pattern
of is found, whatever patterns of other kinds that one has: reasons moved
under another reason, which takes parts.  The report names the patterns
the role belongs to."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Claim
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** First reason
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_BREAKDOWN: parts
:END:
**** Moved under it
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[https://e.x/s][s]]
"
    (let* ((model (org-truss-read))
           (checks (org-truss-checks model)))
      (should (equal (mapcar (lambda (hit) (list (org-truss-member-words (car hit)) (cadr hit)
                                                 (org-truss-member-words (cddr hit))))
                             (plist-get checks :no-pattern))
                     '(("Moved under it" logic "First reason"))))
      (should (equal (org-truss-patterns-with-role 'logic 'reason) '(reasons)))
      (should (string-match-p
               "^f:[0-9]+: Moved under it -- TRUSS_LOGIC_ROLE reason, but First reason has no TRUSS_LOGIC (reasons has it)$"
               (org-truss-check-report model "f"))))))

(ert-deftest org-truss-test-any-pattern-anywhere ()
  "A member and a section take patterns alike, of every kind.  A telling
pattern asks the headings right below for each of its places -- deeper
down, a place is filled for that heading, not this one.  Roles are named
in the file's language."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** We move to fortnightly reviews
:PROPERTIES:
:TRUSS_TELLING: scqa
:END:
*** Reviews run long
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_TELLING: scqa
:END:
** Now
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
** What we do
:PROPERTIES:
:TRUSS_TELLING_ROLE: answer
:TRUSS_BREAKDOWN: 5w1h
:TRUSS_LOGIC: reasons
:END:
*** Why it is so
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: why
:TRUSS_TELLING_ROLE: complication
:END:
"
    (let* ((model (org-truss-read))
           (root (org-truss-model-structure model))
           (what (cadr (org-truss-member-supports root)))
           (move (org-truss-test--m model "We move to fortnightly reviews")))
      (should (equal (org-truss-gaps root) '((telling complication . 1) (telling question . 1))))
      (should (eq (org-truss-member-logic what) 'reasons))
      ;; Why it is so plays reasons' one role, unwritten.
      (should (equal (mapcar #'cadr (org-truss-gaps what)) '(who when where what how)))
      (should (equal (mapcar #'car (plist-get (org-truss-checks model) :gaps))
                     (list move root what)))
      (should (equal (org-truss-gaps move)
                     '((telling complication . 1) (telling question . 1) (telling answer . 1))))
      (should (equal (org-truss-role-label 'sky) "Sky"))
      (let ((org-truss-language 'ja))
        (should (equal (org-truss-role-label 'umbrella) "傘"))
        (should (equal (org-truss-role-label 'who) "誰が"))))))

(ert-deftest org-truss-test-breakdown-is-written-as-a-list ()
  "What is under a heading is written out as a list when one of its
patterns says so: a breakdown, numbered for steps, bulleted else, with
reasons or without.  A part playing a role flagged :label opens with it."
  (org-truss-test--with org-truss-test--how-file
    (let* ((model (org-truss-read))
           (check (org-truss-test--m model "Check before every test"))
           (needs (org-truss-test--m model "What a check needs")))
      (should (eq (org-truss-list-form check) 'bulleted))
      (should (eq (org-truss-labelling-role check (org-truss-test--m model "The driver's manager"))
                  'who))
      (should (eq (org-truss-list-form (org-truss-test--m model "As follows")) 'numbered))
      (should (eq (org-truss-list-form needs) 'bulleted))
      (should-not (org-truss-labelling-role needs (org-truss-test--m model "Someone to check")))
      (should-not (org-truss-list-form (org-truss-test--m model "Tests are safer checked")))))
  (org-truss-test--with (replace-regexp-in-string
                         ":TRUSS_BREAKDOWN: 5w1h" ":TRUSS_BREAKDOWN: 5w1h\n:TRUSS_LOGIC: reasons"
                         org-truss-test--how-file)
    (should (eq (org-truss-list-form (org-truss-test--m (org-truss-read) "Check before every test"))
                'bulleted))))

(ert-deftest org-truss-test-sections-out-of-order ()
  "A section the file has below one its parent's telling pattern tells after
it is out of order, since the document follows the file.  A section in no
place is not judged."
  (org-truss-test--with org-truss-test--unfinished-file
    (let ((late (plist-get (org-truss-checks (org-truss-read)) :out-of-order)))
      (should (equal (mapcar (lambda (o) (cons (org-truss-member-words (car o))
                                               (org-truss-member-words (cdr o))))
                             late)
                     '(("空" . "Rain"))))))
  (should (string-match-p
           "Out of order --.*\n.*: 空 -- below Rain, which TRUSS_TELLING tells after it"
           (org-truss-test--with org-truss-test--unfinished-file
             (org-truss-check-report (org-truss-read) "truss.org")))))

;;;; Grounds

(defconst org-truss-test--grounds-file "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Claim
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** By words
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
the minutes of May
*** By a link
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[moor:6f1c::3][Minutes l. 3]]
*** By a quote
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
#+begin_quote
We agreed.
#+end_quote
*** In its text
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
See [[file:sources/a.pdf][the rule]].
*** Through a member
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[#fact]]
*** Through an argument
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[#argued]]
*** Through a bare one
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[#bare]]
[[#fact]]
*** On a cycle
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[#a]]
*** Assumed                                                       :assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
*** Argued below
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_LOGIC: reasons
:END:
**** Unsupported
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
*** Nothing
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
*** Only broken
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[#gone]]
*** No role
:PROPERTIES:
:TRUSS_LOGIC_ROLE: major
:END:
** Points at a bare one
:PROPERTIES:
:END:
[[#bare]]
[[#argued]]
** Fact
:PROPERTIES:
:CUSTOM_ID: fact
:END:
[[https://e.x/minutes][minutes]]
** Bare
:PROPERTIES:
:CUSTOM_ID: bare
:END:
** Argued
:PROPERTIES:
:CUSTOM_ID: argued
:TRUSS_LOGIC: deduction
:END:
** A
:PROPERTIES:
:CUSTOM_ID: a
:END:
[[#b]]
** B
:PROPERTIES:
:CUSTOM_ID: b
:END:
[[#a]]
** Plan
:PROPERTIES:
:TRUSS_BREAKDOWN: steps
:END:
*** Step one
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
"
  "Reasons with grounds of every kind, and without.")

(ert-deftest org-truss-test-grounds-of-its-own ()
  "A member has grounds in a quotation in its text, or in a link in its
text, to a member or a source.  Words naming a source are none."
  (org-truss-test--with org-truss-test--grounds-file
    (let* ((model (org-truss-read))
           (m (lambda (label) (org-truss-test--m model label))))
      (should (equal (org-truss-member-cited (funcall m "By a link"))
                     "[[moor:6f1c::3][Minutes l. 3]]"))
      (should (equal (org-truss-member-quoted (funcall m "By a quote")) '("We agreed.")))
      (should (equal (org-truss-member-cited (funcall m "In its text"))
                     "[[file:sources/a.pdf][the rule]]"))
      (dolist (label '("By a link" "By a quote" "In its text" "Through a member"))
        (should (org-truss-has-grounds-p (funcall m label))))
      (should-not (org-truss-has-grounds-p (funcall m "By words")))
      (should-not (org-truss-has-grounds-p (funcall m "Nothing")))
      (should (equal (org-truss-member-grounds (funcall m "Through a bare one")) '("bare" "fact")))
      (should-not (org-truss-member-cited (funcall m "Through a bare one"))))))

(ert-deftest org-truss-test-what-must-have-grounds ()
  "A heading that plays a role of the logic of the member above must have
grounds, unless it has a logic of its own, whose reasons must have them
instead, or is an assumption.  Nothing else must: a part of a breakdown,
a heading playing no role, a member under no logic."
  (org-truss-test--with org-truss-test--grounds-file
    (let* ((model (org-truss-read))
           (needs (lambda (label) (org-truss-needs-grounds-p model (org-truss-test--m model label)))))
      (dolist (label '("By words" "Through a member" "Unsupported" "Nothing" "Only broken"))
        (should (funcall needs label)))
      (dolist (label '("Assumed" "Argued below" "No role" "Step one" "Fact" "Claim"))
        (should-not (funcall needs label))))))

(ert-deftest org-truss-test-missing-grounds ()
  "A heading that must have grounds lacks them when its text neither quotes
a source nor links to one or to a member; words naming one are not
enough.  What a link points to is not read."
  (org-truss-test--with org-truss-test--grounds-file
    (let* ((model (org-truss-read))
           (missing (lambda (label) (org-truss-missing-grounds model (org-truss-test--m model label)))))
      (dolist (label '("By a link" "By a quote" "In its text" "Through a member"
                       "Through an argument" "Through a bare one" "On a cycle" "Only broken"
                       "Assumed" "Argued below" "No role"))
        (should-not (funcall missing label)))
      (should (funcall missing "By words"))
      (should (funcall missing "Unsupported"))
      (should (funcall missing "Nothing"))
      (should (equal (org-truss-test--labels (plist-get (org-truss-checks model) :no-grounds))
                     '("By words" "Unsupported" "Nothing"))))))

(ert-deftest org-truss-test-holds ()
  "A member holds when it has grounds, a logic, or the tag :assumption: --
what is asked of a heading that must have grounds."
  (org-truss-test--with org-truss-test--grounds-file
    (let ((model (org-truss-read)))
      (dolist (label '("Fact" "Argued" "Assumed" "By a quote" "A" "Points at a bare one"))
        (should (org-truss-holds-p (org-truss-test--m model label))))
      (dolist (label '("Bare" "Nothing" "Step one"))
        (should-not (org-truss-holds-p (org-truss-test--m model label)))))))

(ert-deftest org-truss-test-weak-grounds ()
  "What any heading points to as grounds must hold: a link in its text to
a member that does not is weak, wherever it is written, whether the
heading must have grounds or not.  One step only: a cycle of members
pointing to each other holds, each having grounds written."
  (org-truss-test--with org-truss-test--grounds-file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-weak-grounds model (org-truss-test--m model "Through a bare one"))
                     '("bare")))
      (should-not (org-truss-weak-grounds model (org-truss-test--m model "On a cycle")))
      (should-not (org-truss-weak-grounds model (org-truss-test--m model "Only broken")))
      (should (equal (mapcar (lambda (w) (cons (org-truss-member-words (car w)) (cdr w)))
                             (plist-get (org-truss-checks model) :weak-grounds))
                     '(("Through a bare one" . "bare") ("Points at a bare one" . "bare")))))))

(ert-deftest org-truss-test-hidden-grounds ()
  "A member the output document tells that stands on one it leaves out --
tagged :noexport:, or under one -- has hidden grounds.  One it does not
tell is not asked."
  (let ((text "* S
:PROPERTIES:
:TRUSS_PART: subject
:END:
** The manual
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
*** Tests run on public roads
:PROPERTIES:
:CUSTOM_ID: roads
:END:
*** Internal figures                                                :noexport:
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
**** Three crashes last year
:PROPERTIES:
:CUSTOM_ID: crashes
:END:
* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Check before every test
:PROPERTIES:
:CUSTOM_ID: check
:TRUSS_LOGIC: reasons
:END:
#+attr_truss:
- The roads are public, [[#roads]]
- It has gone wrong, [[#crashes]]
* T
:PROPERTIES:
:TRUSS_PART: structure
:END:
** [[truss-include:check]]
"))
    (org-truss-test--with text
      (let ((model (org-truss-read)))
        (should (org-truss-left-out-p model (org-truss-test--m model "Three crashes last year")))
        (should-not (org-truss-left-out-p model (org-truss-test--m model "Tests run on public roads")))
        (should (equal (mapcar (lambda (h) (cons (org-truss-member-words (car h)) (cdr h)))
                               (plist-get (org-truss-checks model) :hidden-grounds))
                       '(("It has gone wrong, [[#crashes]]" . "crashes"))))
        (should (string-match-p "^Hidden grounds -- .*\n.*: It has gone wrong, \\[\\[#crashes\\]\\] -- \\[\\[#crashes\\]\\] is left out"
                                (org-truss-check-report model)))))
    (org-truss-test--with (replace-regexp-in-string "^\\*\\* \\[\\[truss-include:check\\]\\]\n" "" text)
      (should-not (plist-get (org-truss-checks (org-truss-read)) :hidden-grounds)))))

(ert-deftest org-truss-test-quote-found ()
  "A quote is found in its source's text with line breaks, spaces and
full- or half-width letters set aside, and the words left out marked …;
a word changed is not found.  A source whose text cannot surely be read
-- a PDF, raw bytes -- is not looked in."
  (org-truss-test--in-directory
      '(("sources/rule.txt" . "4.2 レビュー記録\n開発チームは、設計及び\nコードのレビューを月２回以上行い、その記録を残すこと。\nTeams review designs and code\ntwice a month.\n")
        ("sources/scan.pdf" . "%PDF-1.4 開発チームは"))
    (let ((file (expand-file-name "truss.org" dir))
          (link "[[file:sources/rule.txt][rule 4.2]]"))
      (with-temp-file (expand-file-name "sources/bytes.txt" dir)
        (set-buffer-multibyte nil)
        (insert (unibyte-string #x80 #xff #xfe #x81 #x00 #xc0)))
      (dolist (found '("開発チームは、設計及びコードのレビューを月2回以上行い、その記録を残すこと。"
                       "開発チームは、設計及び コードのレビュー"
                       "開発チームは、…その記録を残すこと。"
                       "Teams review designs and code twice a month."
                       "Teamsreviewdesigns"))
        (should (eq (org-truss-quote-found found link file) 'found)))
      (dolist (missing '("開発チームは、設計とコードのレビュー"
                         "4.2 開発チームは、設計及びコードのレビュー"
                         "その記録を残すこと。…開発チームは"))
        (should (eq (org-truss-quote-found missing link file) 'missing)))
      (should-not (org-truss-quote-found "開発チームは" "[[file:sources/scan.pdf]]" file))
      (should-not (org-truss-quote-found "x" "[[file:sources/bytes.txt]]" file))
      (should-not (org-truss-quote-found "x" "[[https://e.x/rule]]" file))
      (should-not (org-truss-quote-found "x" "[[file:sources/gone.txt]]" file))
      ;; A file in another coding is found, or not looked in where Emacs
      ;; may misread it; never said to lack a quote it holds.
      (dolist (coding '(shift_jis cp932 euc-jp utf-16le utf-8-with-signature utf-8-dos))
        (let ((coding-system-for-write coding))
          (with-temp-file (expand-file-name (format "sources/%s.txt" coding) dir)
            (insert "4.2 レビュー記録\n開発チームは、設計及びコードのレビューを月2回以上行い、その記録を残すこと。\n")))
        (should-not (eq (org-truss-quote-found "開発チームは、設計及びコードのレビュー"
                                               (format "[[file:sources/%s.txt]]" coding) file)
                        'missing)))
      (should (eq (org-truss-quote-found "開発チームは、設計及びコードのレビュー"
                                         "[[file:sources/shift_jis.txt]]" file)
                  'found)))))

(ert-deftest org-truss-test-quotes-not-found ()
  "A quote not in its source is listed for the board, not yet in the
report: how surely quotes are found is still tried on real files.  A
quote under a member linking nowhere is looked for in the source the
member above names."
  (org-truss-test--in-directory
      '(("sources/rule.txt" . "Teams review designs and code twice a month.\n")
        ("truss.org" . "* S\n:PROPERTIES:\n:TRUSS_PART: subject\n:END:\n** The rule\n[[file:sources/rule.txt][rule]]\n*** Reviews are twice a month\n#+begin_quote\nTeams review designs twice a month.\n#+end_quote\n*** Reviews are kept\n#+begin_quote\nTeams review designs and code\n#+end_quote\n"))
    (let ((model (org-truss-read (find-file-noselect (expand-file-name "truss.org" dir)))))
      (should (equal (mapcar (lambda (e) (cons (org-truss-member-words (car e)) (cdr e)))
                             (plist-get (org-truss-checks model) :quotes-not-found))
                     '(("Reviews are twice a month" . "Teams review designs twice a month."))))
      (should-not (string-match-p "Quotes not found" (org-truss-check-report model))))))

(ert-deftest org-truss-test-grounds-set-low ()
  "An apex member whose supporting members, two or more, all stand on the
same member, while it does not, has its grounds set low: it is to stand
on that member, once.  One that stands on it, or a supporting member
that does not, is not listed."
  (let ((text "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** The claim
:PROPERTIES:
:CUSTOM_ID: claim
:END:
** Move to fortnightly
:PROPERTIES:
:TRUSS_BREAKDOWN: steps
:END:
*** Ask the leads
[[#claim]]
*** Change the calendar
# [[#claim]]
"))
    (org-truss-test--with text
      (let ((model (org-truss-read)))
        (should (equal (mapcar (lambda (e) (cons (org-truss-member-words (car e)) (cdr e)))
                               (plist-get (org-truss-checks model) :low-grounds))
                       '(("Move to fortnightly" . "claim"))))
        (should (string-match-p "^Grounds set low -- .*\n.*: Move to fortnightly -- every supporting member stands on \\[\\[#claim\\]\\]"
                                (org-truss-check-report model)))))
    (org-truss-test--with (replace-regexp-in-string "^\\(:TRUSS_BREAKDOWN: steps\n:END:\n\\)" "\\1[[#claim]]\n" text)
      (should-not (plist-get (org-truss-checks (org-truss-read)) :low-grounds)))
    (org-truss-test--with (replace-regexp-in-string "^# \\[\\[#claim\\]\\]\n" "" text)
      (should-not (plist-get (org-truss-checks (org-truss-read)) :low-grounds)))))

(ert-deftest org-truss-test-hidden-reasons ()
  "The apex member of a logic truss the output document tells stands on its
reasons: one tagged :noexport: is hidden grounds, as a link to one is."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Half the items repeat
:PROPERTIES:
:CUSTOM_ID: half
:TRUSS_LOGIC: reasons
:END:
*** Fifty-two percent came back                         :noexport:assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
*** The agendas show it                                          :assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
* T
:PROPERTIES:
:TRUSS_PART: structure
:END:
** [[truss-include:half]]
"
    (let* ((model (org-truss-read))
           (hidden (plist-get (org-truss-checks model) :hidden-grounds)))
      (should (equal (mapcar (lambda (h) (cons (org-truss-member-words (car h))
                                               (org-truss-member-words (cdr h))))
                             hidden)
                     '(("Half the items repeat" . "Fifty-two percent came back"))))
      (should (string-match-p ": Half the items repeat -- Fifty-two percent came back is left out of the output document$"
                              (org-truss-check-report model))))))

(ert-deftest org-truss-test-placeholders ()
  "The words a new file gives its members reach the reader, through
Structure, until they are written over: a part's name, or a role's in
either language.  Those the output document does not tell are not asked."
  (org-truss-test--with (org-truss-skeleton "T")
    (let ((model (org-truss-read)))
      (should (equal (mapcar #'org-truss-member-words (plist-get (org-truss-checks model) :placeholders))
                     '("Subject" "Part" "Part" "Interpretation" "Part" "Reason" "Action" "Step")))
      (should (org-truss-placeholder-p (org-truss-model-structure model)))))
  (org-truss-test--with (replace-regexp-in-string
                         "^\\*\\* Interpretation$" "** 解釈"
                         (replace-regexp-in-string "^\\*\\* Action$" "** Test drivers are checked"
                                                   (org-truss-skeleton "T")))
    (should (equal (mapcar #'org-truss-member-words
                           (seq-filter #'org-truss-member-roles
                                       (plist-get (org-truss-checks (org-truss-read)) :placeholders)))
                   '("Part" "Part" "解釈" "Part" "Reason" "Step")))))

(ert-deftest org-truss-test-grounds-in-the-text ()
  "A link in a heading's text to a member is grounds: it gives the heading
grounds, and what it points to must hold and be there.  A section reads
its text alike, and a section with a logic asks grounds of its reasons as
a member does: a reason stands on what it tells, an item listing a member
too."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Claim
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** Cites a fact
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
As [[#fact]] says.
*** Cites a bare one
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[#bare]]
As [[#bare]] says, twice.
*** Cites nothing there
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
As [[#gone]] says.
** Fact
:PROPERTIES:
:CUSTOM_ID: fact
:END:
[[https://e.x/minutes][minutes]]
** Bare
:PROPERTIES:
:CUSTOM_ID: bare
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_LOGIC: reasons
:END:
** Why
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
- [[truss-include:fact]]
** Because
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
As [[#fact]] shows.
- [[truss-include:bare]]
"
    (let* ((model (org-truss-read))
           (checks (org-truss-checks model))
           (section (lambda (words)
                      (seq-find (lambda (s) (equal (org-truss-member-words s) words))
                                (org-truss-members-in model 'structure))))
           (pairs (lambda (key)
                    (mapcar (lambda (hit) (cons (org-truss-member-words (car hit)) (cdr hit)))
                            (plist-get checks key)))))
      (should (equal (org-truss-member-points (org-truss-test--m model "Cites a fact")) '("fact")))
      (should (org-truss-has-grounds-p (org-truss-test--m model "Cites a fact")))
      (should (equal (funcall pairs :weak-grounds) '(("Cites a bare one" . "bare") ("Because" . "bare"))))
      (should (equal (funcall pairs :broken-grounds) '(("Cites nothing there" . "gone"))))
      (should-not (org-truss-member-points (funcall section "Why")))
      (should (equal (org-truss-member-grounds (funcall section "Why")) '("fact")))
      (should (equal (org-truss-member-grounds (funcall section "Because")) '("bare" "fact")))
      (should-not (plist-get checks :no-grounds)))))

(ert-deftest org-truss-test-reason-told-on-its-line ()
  "A reason whose heading's line tells a member is that member there, and
stands on it: it has grounds, weak when the member does not hold.  Under
a breakdown, or in a section's text, such a link tells and is no ground."
  (org-truss-test--with "* M
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
** Split
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
*** [[truss-include:bare]]
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: part
:END:
** Fact
:PROPERTIES:
:CUSTOM_ID: fact
:END:
[[https://e.x/minutes][minutes]]
** Bare
:PROPERTIES:
:CUSTOM_ID: bare
:END:
"
    (let* ((model (org-truss-read))
           (checks (org-truss-checks model))
           (claim (org-truss-test--m model "Claim"))
           (split (org-truss-test--m model "Split")))
      (should (equal (mapcar #'org-truss-member-grounds (org-truss-member-supports claim))
                     '(("fact") ("bare"))))
      (should-not (plist-get checks :no-grounds))
      (should (equal (mapcar (lambda (w) (cons (org-truss-member-words (car w)) (cdr w)))
                             (plist-get checks :weak-grounds))
                     '(("[[truss-include:bare]]" . "bare"))))
      (should-not (org-truss-member-grounds (car (org-truss-member-supports split)))))))

(ert-deftest org-truss-test-mixed-sources ()
  "The parts with nothing under them keep to one source, and a logic keeps
to one in all it holds, wherever they are.  One taken by org-moor is one
source wherever its links point and whatever they say; a part with parts
under it is one source of its own; links to members are no sources, so
facts of different sources are brought together by pointing to them."
  (org-truss-test--with "* S
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Form
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
*** Field A
[[moor:form::14][the form, l. 14]]
*** Field B
[[moor:form::200][field B]]
** Read together
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
*** The form
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
**** Field C
[[moor:form::3]]
*** The rule
[[moor:rule]]
** Mixed
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
*** Field D
[[moor:form]]
*** A page
[[https://e.x/page][page]]
** Summed up
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** Says one thing
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[moor:rule::2]]
*** Says another
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[file:notes/memo.org::4]]
* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Shares
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
*** One share
[[#a]]
*** Another
[[#b]]
** Read across
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** By the rule
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[moor:rule]]
*** By the form
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
[[moor:form]]
"
    (let ((model (org-truss-read)))
      (should (equal (mapcar (lambda (m) (cons (org-truss-member-words (car m)) (cdr m)))
                             (plist-get (org-truss-checks model) :mixed-sources))
                     '(("Mixed" "moor:form" "https://e.x/page")
                       ("Summed up" "moor:rule" "notes/memo.org")
                       ("Read across" "moor:rule" "moor:form"))))
      (should (string-match-p "^Mixed sources -- .*\n.*:[0-9]+: Mixed -- points into moor:form, https://e.x/page$"
                              (org-truss-check-report model))))))

(defconst org-truss-test--claims-file "* Subject
:PROPERTIES:
:TRUSS_PART: subject
:TRUSS_BREAKDOWN: parts
:END:
** Minutes
:PROPERTIES:
:TRUSS_BREAKDOWN: parts
:END:
*** Eight of twelve ran past the hour
:PROPERTIES:
:CUSTOM_ID: f1
:END:
*** Half the items came back
:PROPERTIES:
:CUSTOM_ID: f2
:END:
*** Urgent ones were settled in chat
:PROPERTIES:
:CUSTOM_ID: f3
:END:
* Message
:PROPERTIES:
:TRUSS_PART: message
:TRUSS_BREAKDOWN: interpretation-action
:END:
** Interpretation
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: interpretation
:TRUSS_BREAKDOWN: parts
:END:
*** The weekly review does not get through its items
:PROPERTIES:
:CUSTOM_ID: c1
:END:
#+attr_truss: :logic reasons
- [[truss-include:f1]]
- [[truss-include:f2]]
*** It drags on
# [[#f2]] [[#f1]]
*** Nothing urgent waits
:PROPERTIES:
:CUSTOM_ID: c2
:TRUSS_LOGIC: reasons
:END:
**** Chat settles it                                             :assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
** Action
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: action
:TRUSS_BREAKDOWN: steps
:END:
*** Meet every other week
:PROPERTIES:
:CUSTOM_ID: a1
:END:
# [[#c1]] [[#c2]]
*** Move the calendar
# [[#a1]]
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
- [[truss-include:m0]]
- [[truss-include:c1]]
"
  "Claims: one said again, two not worth a heading of their own.")

(ert-deftest org-truss-test-checks-claims-said-again ()
  (org-truss-test--with org-truss-test--claims-file
    (let* ((model (org-truss-read))
           (said (plist-get (org-truss-checks model) :said-again)))
      (should (equal (mapcar (lambda (e) (list (org-truss-member-words (car e)) (cadr e)
                                               (mapcar #'org-truss-member-words (cddr e))))
                             said)
                     '(("The weekly review does not get through its items" ("f1" "f2") ("It drags on"))
                       ("It drags on" ("f1" "f2") ("The weekly review does not get through its items")))))
      (should (string-match-p "^Said again -- .*\n.*:[0-9]+: The weekly review does not get through its items -- stands on \\[\\[#f1\\]\\] \\[\\[#f2\\]\\], as It drags on does$"
                              (org-truss-check-report model))))))

(ert-deftest org-truss-test-checks-claims-not-a-heading ()
  (org-truss-test--with org-truss-test--claims-file
    (let* ((model (org-truss-read))
           (unearned (plist-get (org-truss-checks model) :unearned)))
      ;; c1 is used by the step and by Structure, on two facts; the step
      ;; and Interpretation are no claims, nor the reason under c2.
      (should (equal (mapcar (lambda (e) (list (org-truss-member-words (car e))
                                               (length (cadr e)) (cddr e)))
                             unearned)
                     '(("It drags on" 0 2)
                       ("Nothing urgent waits" 1 1))))
      (should (string-match-p ":[0-9]+: Nothing urgent waits -- used in 1 place, on 1 ground$"
                              (org-truss-check-report model))))))

(ert-deftest org-truss-test-checks-claims-used-by-including-above ()
  (org-truss-test--with (replace-regexp-in-string
                         "- \\[\\[truss-include:m0\\]\\]\n" "- [[truss-include:i]]\n"
                         (replace-regexp-in-string
                          ":TRUSS_BREAKDOWN_ROLE: interpretation\n"
                          ":TRUSS_BREAKDOWN_ROLE: interpretation\n:CUSTOM_ID: i\n"
                          org-truss-test--claims-file))
    ;; Structure includes Interpretation whole: that uses every claim in it.
    (let ((model (org-truss-read)))
      (should (equal (mapcar (lambda (e) (list (org-truss-member-words (car e))
                                               (length (cadr e)) (cddr e)))
                             (plist-get (org-truss-checks model) :unearned))
                     '(("It drags on" 1 2)
                       ("Nothing urgent waits" 2 1)))))))

(defconst org-truss-test--includes-file "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Move to fortnightly
:PROPERTIES:
:CUSTOM_ID: move
:END:
We move, as [[truss-include:long]] shows.
- [[truss-include:loop]]
# Not told here: [[truss-include:gone]]
** Reviews run long
:PROPERTIES:
:CUSTOM_ID: long
:END:
** Loops back
:PROPERTIES:
:CUSTOM_ID: loop
:END:
*** Under it
[[truss-include:move]]
** Not told
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[truss-include:move]]
- [[truss-include:gone]]
"
  "Members telling members, one of them back, and a link that tells none.")

(ert-deftest org-truss-test-includes ()
  "Any heading tells members by its links, in a sentence or on a line of
their own, and a link in a comment tells nothing: the document tells what
the sections tell and what that tells in turn.  A link that tells no
member is broken, and one that tells a member which, with what is nested
under it, tells the heading back is a loop."
  (org-truss-test--with org-truss-test--includes-file
    (let* ((model (org-truss-read))
           (move (org-truss-test--m model "Move to fortnightly"))
           (checks (org-truss-checks model))
           (pairs (lambda (key) (mapcar (lambda (hit) (cons (org-truss-member-words (car hit)) (cdr hit)))
                                        (plist-get checks key)))))
      (should (equal (org-truss-member-includes move) '("long" "loop")))
      (should-not (org-truss-member-points move))
      (should (equal (org-truss-test--labels (org-truss-in-document model))
                     '("Move to fortnightly" "Reviews run long" "Loops back" "Under it")))
      (should (equal (funcall pairs :broken-links) '(("Now" . "gone"))))
      (should (equal (funcall pairs :loops) '(("Move to fortnightly" . "loop") ("Under it" . "move")))))))

(ert-deftest org-truss-test-sources-must-be-there ()
  "A link to a source points to something there: a file, by a path from the
truss file's directory, a search after :: aside; an attachment of its
heading; a source taken by org-moor, when org-moor can say.  A page on the
web is not looked for.  Each that points to nothing is a broken link."
  (org-truss-test--in-directory '(("sources/law.pdf" . "%PDF"))
    (let ((file (expand-file-name "truss.org" dir))
          (org-truss-moor-missing-function (lambda (id _file) (not (equal id "kept")))))
      (with-temp-file file
        (insert "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** Cites what is there
:PROPERTIES:
:END:
[[file:sources/law.pdf::3][the law]]
[[moor:kept::2][kept]]
See [[./sources/law.pdf]] and [[https://example.com/gone]].
** Cites what is not
:PROPERTIES:
:END:
[[moor:lost][lost]]
See [[file:sources/gone.pdf][gone]], and [[attachment:shot.png]].
"))
      (with-current-buffer (find-file-noselect file)
        (let* ((model (org-truss-read))
               (broken (plist-get (org-truss-checks model) :broken-sources)))
          (should (equal (org-truss-member-source-links (org-truss-test--m model "Cites what is there"))
                         '("[[file:sources/law.pdf::3][the law]]" "[[moor:kept::2][kept]]"
                           "[[./sources/law.pdf]]" "[[https://example.com/gone]]")))
          (should (equal (mapcar (lambda (b) (cons (org-truss-member-words (car b)) (cdr b))) broken)
                         '(("Cites what is not" . "[[moor:lost][lost]]")
                           ("Cites what is not" . "[[file:sources/gone.pdf][gone]]")
                           ("Cites what is not" . "[[attachment:shot.png]]"))))
          (should (string-match-p "^truss\\.org:[0-9]+: Cites what is not -- \\[\\[moor:lost\\]\\[lost\\]\\] not found$"
                                  (org-truss-check-report model))))
        (let ((org-truss-moor-missing-function nil))
          (should (equal (length (plist-get (org-truss-checks (org-truss-read)) :broken-sources)) 2)))))))

(ert-deftest org-truss-test-grounds-are-written ()
  "A ground is written in the text, a link on a comment line of its own
after the heading's last line, which the reader is not told; taking it
away takes that line, and leaves a link among other words, for the words
to be rewritten."
  (org-truss-test--with org-truss-test--file
    (let ((half (org-truss-test--heading-pos "Half the items repeat")))
      (org-truss-add-ground half "aside")
      (should (string-match-p "shows\\.\n# \\[\\[#aside\\]\\]\n\\*\\*\\* Agenda diff" (buffer-string)))
      (should-not (string-match-p "aside" (or (org-truss-member-body
                                               (org-truss-test--m (org-truss-read) "Half the items repeat"))
                                              "")))
      (should (equal (org-truss-member-grounds (org-truss-test--m (org-truss-read) "Half the items repeat"))
                     '("long" "diff" "aside")))
      (should (org-truss-remove-ground half "aside"))
      (should (org-truss-remove-ground half "long"))
      (should-not (org-truss-remove-ground half "diff"))
      (should (equal (org-truss-member-grounds (org-truss-test--m (org-truss-read) "Half the items repeat"))
                     '("diff" "long")))
      (should (string-match-p "^:END:\n# Robin keeps" (buffer-string))))
    (let ((pos (org-truss-test--heading-pos "Lone remark")))
      (should (org-truss-toggle-assumption pos))
      (should (org-truss-assumption-p (org-truss-test--m (org-truss-read) "Lone remark")))
      (should-not (org-truss-toggle-assumption pos))
      (should-not (org-truss-assumption-p (org-truss-test--m (org-truss-read) "Lone remark"))))))

;;;; What is left to do

(ert-deftest org-truss-test-checks ()
  "Each thing left to do is found where it is: a missing role at the
heading whose pattern asks, missing grounds at the heading that lacks
them, a broken link where it is written."
  (org-truss-test--with org-truss-test--file
    (let* ((model (org-truss-read))
           (checks (org-truss-checks model)))
      (should (equal (mapcar (lambda (g) (cons (org-truss-member-words (car g)) (cdr g)))
                             (plist-get checks :gaps))
                     '(("Brief" (breakdown question . 1) (breakdown response . 1)
                        (breakdown constraints . 1))
                       ("Move to fortnightly" (logic minor . 1)))))
      (should-not (plist-get checks :no-role))
      (should-not (plist-get checks :no-pattern))
      (should-not (plist-get checks :out-of-order))
      (should (equal (org-truss-test--labels (plist-get checks :no-grounds))
                     '("Some items are urgent" "A meeting that repeats itself can meet less")))
      (should (equal (mapcar #'cdr (plist-get checks :broken-links)) '("none")))
      (should-not (plist-get checks :broken-grounds))
      (should-not (plist-get checks :duplicates))))
  (org-truss-test--with (replace-regexp-in-string
                         "^# \\[\\[#half\\]\\]$" "# [[#half]] [[#gone]]"
                         org-truss-test--file)
    (let ((checks (org-truss-checks (org-truss-read))))
      (should (equal (mapcar (lambda (b) (cons (org-truss-member-words (car b)) (cdr b)))
                             (plist-get checks :broken-grounds))
                     '(("Move to fortnightly" . "gone")))))))

(ert-deftest org-truss-test-check-report ()
  "The report names each check that finds something, says what it finds,
and gives each thing found a line of its own that compilation mode reads."
  (org-truss-test--with org-truss-test--file
    (let ((report (org-truss-check-report (org-truss-read) "truss.org")))
      (should (string-match-p "^Broken links -- links that point to nothing" report))
      (should (string-match-p "^truss\\.org:[0-9]+: \\[\\[truss-include:none\\]\\] in Umbrella not found$"
                              report))
      (should (string-match-p "^truss\\.org:[0-9]+: Some items are urgent -- no grounds: a link or a quote, a TRUSS_LOGIC, or :assumption:$" report))
      (should (string-match-p
               "^truss\\.org:[0-9]+: Move to fortnightly -- lacks TRUSS_LOGIC_ROLE minor (logic › deduction)$"
               report))
      (should (< (string-match "^Broken links" report) (string-match "^No grounds" report)
                 (string-match "^Missing roles" report)))
      (let ((line (and (string-match "^truss\\.org:\\([0-9]+\\): Some items are urgent" report)
                       (string-to-number (match-string 1 report)))))
        (should (equal (progn (goto-char (point-min)) (forward-line (1- line))
                              (buffer-substring (point) (line-end-position)))
                       "*** Some items are urgent")))))
  (org-truss-test--with org-truss-test--grounds-file
    (let ((report (let ((org-truss-moor-missing-function nil))
                    (org-truss-check-report (org-truss-read) "f"))))
      (should (string-match-p "^f:[0-9]+: No role -- no TRUSS_LOGIC_ROLE of logic › reasons, under Claim$"
                              report))
      (should (string-match-p "^f:[0-9]+: Only broken -- \\[\\[#gone\\]\\] not found$" report))
      (should (string-match-p "^f:[0-9]+: Through a bare one -- \\[\\[#bare\\]\\] has no grounds$" report))))
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
"
    (should (equal (org-truss-check-report (org-truss-read) "f") "Nothing is left to do.\n"))))

(ert-deftest org-truss-test-told ()
  "The document tells what its sections list, with what is nested under it."
  (org-truss-test--with org-truss-test--file
    (should (equal (org-truss-test--labels (org-truss-in-document (org-truss-read)))
                   '("Reviews run long" "Half the items repeat" "Agenda diff"
                     "Items need a week to move" "Some items are urgent"
                     "Urgent items go to chat" "Who decides what is urgent"
                     "Move to fortnightly" "A meeting that repeats itself can meet less")))))

(ert-deftest org-truss-test-duplicates ()
  "Two headings with one id are reported, since a link cannot tell them
apart, members or sections alike; two with one label are not, since
nothing points by label."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: message
:END:
** One
:PROPERTIES:
:CUSTOM_ID: x
:END:
** Two
:PROPERTIES:
:CUSTOM_ID: x
:END:
** Same
** Same
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Three
:PROPERTIES:
:CUSTOM_ID: x
:END:
"
    (let ((model (org-truss-read)))
      (should (equal (org-truss-model-duplicates model) '("x")))
      (should (equal (org-truss-member-words (org-truss-member-by-id model "x")) "One"))
      (should (string-match-p "^f:[0-9]+: Two -- #x, which another member has too$"
                              (org-truss-check-report model "f")))
      (should (string-match-p "^f:[0-9]+: Three -- #x, which another member has too$"
                              (org-truss-check-report model "f"))))))

;;;; Reading

(ert-deftest org-truss-test-text ()
  "A pointing link in a member's text, in a comment or in what the output
document shows, points to a member; one in a drawer does not, nor does an
include link.  The output document shows the text outside the comments; a
# in a block is no comment."
  (org-truss-test--with org-truss-test--file
    (let ((parsed (org-truss--text-at (org-truss-test--heading-pos "Half the items repeat"))))
      (should (equal (org-truss--points-in (plist-get parsed :all)) '("long" "diff" "long")))
      (should-not (plist-get parsed :includes))
      (should (equal (plist-get (org-truss--text-at (org-truss-test--heading-pos "Sky")) :includes)
                     '("long")))
      (should (equal (plist-get parsed :body)
                     "Half of each agenda repeats the week before, as [[#long]] shows.\n"))
      (should (equal (plist-get parsed :comments)
                     "[[#long]]\nRobin keeps raising the same items; see [[#diff]].\n")))
    (org-truss-test--with "* H\nTold.\n#+begin_comment\nKept, [[#a]].\n#+end_comment\n#+begin_src sh\n# told too\n#+end_src\n#\n"
      (let ((parsed (org-truss--text-at (point-min))))
        (should (equal (plist-get parsed :body) "Told.\n#+begin_src sh\n# told too\n#+end_src\n"))
        (should (equal (plist-get parsed :comments) "Kept, [[#a]].\n\n"))
        (should (equal (org-truss--points-in (plist-get parsed :all)) '("a")))))
    (let ((parsed (org-truss--text-at (org-truss-test--heading-pos "Half the items repeat"))))
      (should (equal (plist-get parsed :props) '(("CUSTOM_ID" . "half")
                                                 ("TRUSS_LOGIC" . "reasons")))))))

(ert-deftest org-truss-test-references ()
  "A link or a ground points to a member by its CUSTOM_ID, and a link that
tells one names it by its CUSTOM_ID too.  One that names a heading points
to no member, and shows as broken."
  (should (equal (org-truss--points-in "[[#a]] and [[#b][words]], [[*C]] [[https://x]] [[truss-include:d]]")
                 '("a" "b" "*C")))
  (should (equal (org-truss--includes-in "[[truss-include:d]] [[#a]] [[truss-include:e][E]]")
                 '("d" "e")))
  (should (equal (org-truss--include-item "a") "- [[truss-include:a]]\n"))
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-member-words (org-truss-member-by-id model "half"))
                     "Half the items repeat"))
      (should (equal (org-truss-member-id (org-truss-test--m model "Lone remark")) nil))
      (should-not (org-truss-member-by-id model "Half the items repeat")))))

(defconst org-truss-test--items-file "#+title: T
* Subject
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Six of twelve items come back
:PROPERTIES:
:CUSTOM_ID: m2
:END:
# [[https://e.x/agendas][agendas]]
* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** We move to fortnightly reviews
:PROPERTIES:
:CUSTOM_ID: m1
:END:
We would meet half as often.
#+attr_truss: :logic reasons :breakdown pros-cons
- pros :: <<m21>>Less time in meetings
  # [[#m2]]
  An hour a fortnight back.
- cons :: Items wait longer
  #+attr_truss: :breakdown steps
  1. Ask the leads
  2. Ask the team
- 人 :: Robin likes it, as [[m21]] says

After the list.
*** A heading under it too
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
- [[truss-include:m1]]
"
  "A member whose reasons are items of a list in its text.")

(ert-deftest org-truss-test-items-are-members ()
  "The items of a list marked #+attr_truss are members right under the
heading whose text holds them, before the headings under it: the list
gives the heading its patterns, an item's term the role it plays, a
pattern of one role is played without one, and a term naming no role is
the item's words.  Its first line is its words, a target in it its id;
the rest of its text its text, a comment left out; a list marked so in
it, the members under it.  The heading's text leaves the list out."
  (org-truss-test--with org-truss-test--items-file
    (let* ((model (org-truss-read))
           (move (org-truss-test--m model "We move to fortnightly reviews"))
           (less (org-truss-member-by-id model "m21"))
           (wait (org-truss-test--m model "Items wait longer"))
           (likes (org-truss-test--m model "人 :: Robin likes it, as [[m21]] says")))
      (should (eq (org-truss-member-logic move) 'reasons))
      (should (eq (org-truss-member-breakdown move) 'pros-cons))
      (should (equal (org-truss-member-body move) "We would meet half as often.\n\nAfter the list."))
      (should (equal (org-truss-test--labels (org-truss-member-supports move))
                     '("Less time in meetings" "Items wait longer"
                       "人 :: Robin likes it, as [[m21]] says" "A heading under it too")))
      (should (equal (org-truss-member-words less) "Less time in meetings"))
      (should (equal (org-truss-member-roles less) '((logic . reason) (breakdown . pros))))
      (should (equal (org-truss-member-roles likes) '((logic . reason))))
      (should (equal (org-truss-member-body less) "An hour a fortnight back."))
      (should (equal (org-truss-member-notes less) "[[#m2]]"))
      (should (equal (org-truss-member-grounds less) '("m2")))
      (should (equal (org-truss-member-grounds likes) '("m21")))
      (should (= (org-truss-member-holder less) (org-truss-member-pos move)))
      (should (= (org-truss-member-level less) 3))
      (should (eq (org-truss-member-breakdown wait) 'steps))
      (should (equal (mapcar #'org-truss-member-roles (org-truss-member-supports wait))
                     '(((breakdown . step)) ((breakdown . step)))))
      (should (eq (org-truss-parent model less) move))
      (let ((checks (org-truss-checks model)))
        ;; The heading under it plays reasons' one role unwritten, as an
        ;; item does, and pros-cons' none.
        (should (equal (org-truss-test--labels (plist-get checks :no-grounds))
                       '("Items wait longer" "A heading under it too")))
        (should (equal (mapcar (lambda (hit) (org-truss-member-words (car hit))) (plist-get checks :no-role))
                       '("人 :: Robin likes it, as [[m21]] says" "A heading under it too")))))))

(defconst org-truss-test--part-items-file "#+title: T
* Brief
:PROPERTIES:
:TRUSS_PART: brief
:END:
#+attr_truss: :breakdown reader-question-response-constraints
- reader :: The team leads
- question :: Do we still need weekly reviews?
- response :: They agree to fortnightly
- constraints :: One page
* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
#+attr_truss:
- <<m1>>We move to fortnightly reviews
  #+attr_truss: :logic reasons
  - Reviews run long
    # [[#m2]]
** Reviews take an hour
:PROPERTIES:
:CUSTOM_ID: m2
:END:
* Structure
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_TELLING: sky-rain-umbrella
:END:
We propose a change.
#+attr_truss:
- sky :: Where we are
  - [[truss-include:m2]]
- rain :: Why change
- umbrella :: [[truss-include:m1]]
** Next
"
  "Parts and the structure whose members and sections are items of a list.")

(ert-deftest org-truss-test-items-under-parts-and-sections ()
  "A list marked #+attr_truss holds headings in the text of a part, members
written in that part, and in the text of a section, sections: the part's
or section's patterns, the roles the items play, before the headings
under it.  A section's other lists stay its text."
  (org-truss-test--with org-truss-test--part-items-file
    (let* ((model (org-truss-read))
           (brief (org-truss-model-brief model))
           (root (org-truss-model-structure model))
           (move (org-truss-member-by-id model "m1"))
           (sky (car (org-truss-member-supports root))))
      (should (eq (org-truss-member-breakdown brief) 'reader-question-response-constraints))
      (should (equal (mapcar #'org-truss-member-roles (org-truss-member-supports brief))
                     '(((breakdown . reader)) ((breakdown . question))
                       ((breakdown . response)) ((breakdown . constraints)))))
      (should (eq (org-truss-member-part (car (org-truss-member-supports brief))) 'brief))
      (should-not (org-truss-gaps brief))
      (should (equal (org-truss-test--labels (org-truss-message-supports model))
                     '("We move to fortnightly reviews" "Reviews take an hour")))
      (should (eq (org-truss-member-part move) 'message))
      (should (= (org-truss-member-level move) 2))
      (should (eq (org-truss-member-logic move) 'reasons))
      (should (equal (mapcar #'org-truss-member-words (org-truss-member-supports root))
                     '("Where we are" "Why change" "[[truss-include:m1]]" "Next")))
      (should (cl-every #'org-truss-in-structure-p (org-truss-member-supports root)))
      (should (equal (org-truss-member-roles sky) '((telling . sky))))
      (should (equal (org-truss-member-includes sky) '("m2")))
      (should (equal (org-truss-member-body sky) "- [[truss-include:m2]]"))
      (should (equal (org-truss-member-body root) "We propose a change."))
      (should (= (org-truss-member-holder sky) (org-truss-member-pos root)))
      (should-not (org-truss-gaps root))
      (should-not (plist-get (org-truss-checks model) :no-grounds)))))

(ert-deftest org-truss-test-no-relation ()
  "A member with members right under it and no pattern says no relation to
them, and is found, a part as any member; one with a pattern in its
property or in its list's #+attr_truss is not."
  (org-truss-test--with org-truss-test--part-items-file
    (let ((model (org-truss-read)))
      (should (equal (plist-get (org-truss-checks model) :no-relation)
                     (list (org-truss-model-message model))))
      (should (string-match-p "^truss\\.org:[0-9]+: Message -- members under it, and no pattern saying what they are to it$"
                              (org-truss-check-report model "truss.org")))))
  (org-truss-test--with (replace-regexp-in-string
                         "#\\+attr_truss:\n- <<m1>>" "#+attr_truss: :breakdown parts\n- part :: <<m1>>"
                         org-truss-test--part-items-file t t)
    (should-not (plist-get (org-truss-checks (org-truss-read)) :no-relation))))

(ert-deftest org-truss-test-truss-shape ()
  "An apex member whose supporting members are all end members is the
apex of a simple truss; one with an apex member among them, of a compound
truss.  A supporting member that is an include link alone is an end
member, and a member with no pattern is no apex member."
  (org-truss-test--with org-truss-test--items-file
    (let ((model (org-truss-read)))
      (should (eq (org-truss-truss-shape (org-truss-test--m model "We move to fortnightly reviews"))
                  'compound))
      (should (eq (org-truss-truss-shape (org-truss-test--m model "Items wait longer")) 'simple))
      (should-not (org-truss-truss-shape (org-truss-test--m model "Six of twelve items come back")))))
  (org-truss-test--with org-truss-test--part-items-file
    (let* ((model (org-truss-read))
           (umbrella (car (last (butlast (org-truss-member-supports (org-truss-model-structure model)))))))
      (should (eq (org-truss-truss-shape (org-truss-model-brief model)) 'simple))
      (should (equal (org-truss-member-words umbrella) "[[truss-include:m1]]"))
      (should (eq (org-truss-truss-shape (org-truss-model-structure model)) 'simple))
      (should (eq (org-truss-truss-shape (org-truss-model-message model)) nil))))
  (org-truss-test--with org-truss-test--clusters-file
    (should (eq (org-truss-truss-shape (org-truss-model-subject (org-truss-read))) 'simple))))

(ert-deftest org-truss-test-items-take-ids-and-grounds ()
  "An item is given a target where its words start, the next id free among
headings and items; a ground on it is written [[id]], and taken away so."
  (org-truss-test--with org-truss-test--items-file
    (let ((wait (save-excursion (goto-char (point-min)) (search-forward "- cons ::")
                                (line-beginning-position)))
          (move (org-truss-test--heading-pos "We move to fortnightly reviews"))
          (subject (org-truss-test--heading-pos "Six of twelve items come back")))
      (should (equal (org-truss-ensure-id wait) "m22"))
      (should (string-match-p "^- cons :: <<m22>>Items wait longer$" (buffer-string)))
      (should (equal (org-truss-ensure-id wait) "m22"))
      (should (equal (org-truss-ensure-id move) "m1"))
      (org-truss-add-ground subject "m22")
      (should (string-match-p "^# \\[\\[m22\\]\\]$" (buffer-string)))
      (should (equal (org-truss-member-grounds (org-truss-test--m (org-truss-read) "Six of twelve items come back"))
                     '("m22")))
      (should (org-truss-remove-ground subject "m22"))
      (should-not (string-match-p "\\[\\[m22\\]\\]" (buffer-string))))))

(ert-deftest org-truss-test-ensure-id ()
  "A member is given m and the next free number, once; one it has stays."
  (org-truss-test--with (concat org-truss-test--file "* X\n:PROPERTIES:\n:CUSTOM_ID: m4\n:END:\n")
    (should (equal (org-truss-ensure-id (org-truss-test--heading-pos "Lone remark")) "m5"))
    (should (equal (org-truss-ensure-id (org-truss-test--heading-pos "Lone remark")) "m5"))
    (should (equal (org-truss-ensure-id (org-truss-test--heading-pos "Reviews run long")) "long"))
    (should (equal (org-truss-ensure-id (org-truss-test--heading-pos "Agenda diff")) "diff"))
    (should (equal (org-truss-member-id (org-truss-test--m (org-truss-read) "Lone remark")) "m5"))
    (should (string-match-p "^\\*\\* Lone remark\n:PROPERTIES:\n:CUSTOM_ID: m5\n:END:\n" (buffer-string)))
    (should (equal (org-truss-ensure-id (org-truss-test--heading-pos "Urgent items go to chat")) "m6"))
    (should (string-match-p (concat "Urgent items go to chat\n:PROPERTIES:\n:CUSTOM_ID: m6\n"
                                    ":TRUSS_BREAKDOWN_ROLE: part\n:END:\n")
                            (buffer-string)))))

(defun org-truss-test--fields (part)
  "Return the members right under PART, its fields, as (ROLES . TEXT)."
  (mapcar (lambda (field) (cons (org-truss-member-roles field) (or (org-truss-member-body field) "")))
          (org-truss-member-supports part)))

(ert-deftest org-truss-test-brief ()
  "A brief field is its text, without the guidance drawer, and plays the
role its TRUSS_BREAKDOWN_ROLE names."
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-model-title model) "Fortnightly reviews"))
      (should (equal (org-truss-test--fields (org-truss-model-brief model))
                     '((((breakdown . reader)) . "The team leads.")))))))

(ert-deftest org-truss-test-conditions ()
  "A field of the brief or the subject is a member, read and judged as any
other, as are the members under it; its text is its body.  The parts are
broken down into their fields: what their breakdown asks for and no field
plays is a missing role."
  (org-truss-test--with org-truss-test--conditions-file
    (let* ((model (org-truss-read))
           (subject (org-truss-model-subject model)))
      (should (equal (org-truss-test--fields subject)
                     '((((breakdown . present)) . "")
                       (((breakdown . future)) . "Finance said so at the October meeting."))))
      (should (equal (org-truss-test--labels
                      (org-truss-member-supports (cadr (org-truss-member-supports subject))))
                     '("No budget this year" "The schedule is fixed")))
      (should (eq (org-truss-parent model (org-truss-test--m model "The schedule is fixed"))
                  (cadr (org-truss-member-supports subject))))
      (should (eq (org-truss-parent model (cadr (org-truss-member-supports subject))) subject))
      (should (equal (plist-get (org-truss-checks model) :gaps)
                     (list (cons (org-truss-model-brief model) '((breakdown constraints . 1)))
                           (cons subject '((breakdown past . 1))))))
      (should (eq (org-truss-member-at model (org-truss-member-pos subject)) subject))
      (should (eq (org-truss-member-part (org-truss-test--m model "No budget this year")) 'subject))
      (should (equal (org-truss-test--labels (org-truss-in-document model)) '("No budget this year")))
      (should (equal (org-truss-test--labels (org-truss-contents model))
                     '("Reader" "Their question" "Response wanted" "Issue"
                       "Nobody checks before a test" "Constraints" "No budget this year"
                       "The schedule is fixed" "Check with a breathalyser"))))))

(ert-deftest org-truss-test-subject-and-members-alike ()
  "Facts summed up in the subject are the reasons of the member summing them
up, each with its grounds; steps in the members need none.  Where a member
is written changes nothing of how it is read."
  (org-truss-test--with org-truss-test--clusters-file
    (let* ((model (org-truss-read))
           (head (org-truss-test--m model "The manager checks every driver before and after driving")))
      (should (eq (org-truss-member-part head) 'subject))
      (should (eq (org-truss-member-part (org-truss-test--m model "The rule may apply to us")) 'message))
      (should (eq (org-truss-member-logic head) 'reasons))
      (should (org-truss-needs-grounds-p model (org-truss-test--m model "The check may be made by video")))
      (should-not (org-truss-needs-grounds-p model (org-truss-test--m model "The manager reads it")))
      (should-not (plist-get (org-truss-checks model) :no-grounds))
      (should-not (plist-get (org-truss-checks model) :no-role)))))

(ert-deftest org-truss-test-nothing-is-read-into-a-heading ()
  "What is nested under a member is what its patterns say, and nothing when
it has none: no reasons that must have grounds, no roles to play."
  (org-truss-test--with (replace-regexp-in-string
                         ":CUSTOM_ID: rule\n:TRUSS_LOGIC: reasons\n" ":CUSTOM_ID: rule\n"
                         org-truss-test--clusters-file)
    (let* ((model (org-truss-read))
           (head (org-truss-test--m model "The manager checks every driver before and after driving")))
      (should-not (org-truss-member-patterns head))
      (should-not (org-truss-needs-grounds-p model (org-truss-test--m model "The check may be made by video")))
      (should-not (org-truss-no-role head))
      (should-not (org-truss-gaps head)))))

(ert-deftest org-truss-test-steps ()
  "Under a member broken down into steps, what is nested is its steps: its
parts, not its reasons, which need no grounds.  What is under a step is
no reason either, unless the step has a logic."
  (org-truss-test--with org-truss-test--steps-file
    (let* ((model (org-truss-read))
           (check (org-truss-test--m model "Check before every test")))
      (should (eq (org-truss-list-form check) 'numbered))
      (should (equal (org-truss-member-grounds check) '("law")))
      (should-not (org-truss-needs-grounds-p model (org-truss-test--m model "Meet the driver face to face")))
      (should-not (org-truss-needs-grounds-p model (org-truss-test--m model "A video call counts as face to face")))
      (should-not (plist-get (org-truss-checks model) :no-grounds))
      (should-not (plist-get (org-truss-checks model) :gaps)))))

(ert-deftest org-truss-test-reads-attachments-as-files ()
  "A link to what is attached to a heading reads, in the model, as a link
to the file, from the truss file's directory; the file itself is not
changed.  Where the heading has nothing attached, the link stays."
  (org-truss-test--in-directory '(("attach/ab/cdef/shot.png" . "png"))
    (let ((file (expand-file-name "truss.org" dir)))
      (with-temp-file file
        (insert "# -*- org-attach-id-dir: \"attach/\"; -*-
#+title: T
* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
** A claim
:PROPERTIES:
:ID:       abcdef
:END:
[[attachment:shot.png]]
# See [[attachment:shot.png][the shot]].
** Another
[[attachment:shot.png]]
"))
      (with-current-buffer (find-file-noselect file)
        (unwind-protect
            (let* ((model (org-truss-read))
                   (claim (org-truss-member-by-words model "A claim")))
              (should (equal (org-truss-member-body claim)
                             "[[file:attach/ab/cdef/shot.png]]"))
              (should (equal (org-truss-member-notes claim)
                             "See [[file:attach/ab/cdef/shot.png][the shot]]."))
              (should (equal (org-truss-member-body (org-truss-member-by-words model "Another"))
                             "[[attachment:shot.png]]"))
              (should (string-match-p "^\\[\\[attachment:shot\\.png\\]\\]\n# See"
                                      (buffer-string))))
          (kill-buffer))))))

;;;; Editing Structure

(ert-deftest org-truss-test-apply-telling ()
  "A heading under a member of Structure takes the place of the one new
member whose telling role it plays, as it is; the pattern adds the rest,
and what plays no role stays at the end."
  (org-truss-test--with (replace-regexp-in-string
                         ":TRUSS_TELLING_ROLE: umbrella" ":TRUSS_TELLING_ROLE: answer"
                         (replace-regexp-in-string ":TRUSS_TELLING_ROLE: sky" ":TRUSS_TELLING_ROLE: situation"
                                                   org-truss-test--file))
    (org-truss-apply-telling (org-truss--part-pos "structure") 'scqa)
    (let* ((model (org-truss-read))
           (root (org-truss-model-structure model))
           (by-label (lambda (l) (seq-find (lambda (s) (equal (org-truss-member-words s) l))
                                           (org-truss-member-supports root)))))
      (should (eq (org-truss-member-telling root) 'scqa))
      (should (equal (org-truss-test--section-labels root)
                     '("Sky" "Complication" "Question" "Umbrella" "Rain")))
      (should (equal (org-truss-member-includes (funcall by-label "Sky"))
                     '("long")))
      (should (equal (org-truss-member-includes (funcall by-label "Umbrella"))
                     '("move" "none")))
      (should (eq (org-truss-member-role (funcall by-label "Umbrella") 'telling) 'answer))
      (should (eq (org-truss-member-role (funcall by-label "Question") 'telling) 'question))
      (should (string-match-p "^\\*\\* Question\n:PROPERTIES:\n:TRUSS_TELLING_ROLE: question\n:END:"
                              (buffer-string)))
      (should (equal (org-truss-member-includes (funcall by-label "Rain"))
                     '("half"))))))

(ert-deftest org-truss-test-apply-pattern-fills-a-place-twice ()
  "Two sections filling the same place both take it, in order."
  (org-truss-test--with "* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
:PROPERTIES:
:TRUSS_TELLING_ROLE: sky
:END:
** Then
:PROPERTIES:
:TRUSS_TELLING_ROLE: sky
:END:
"
    (org-truss-apply-telling (org-truss--part-pos "structure") 'sky-rain-umbrella)
    (let ((sections (org-truss-member-supports (org-truss-model-structure (org-truss-read)))))
      (should (equal (mapcar #'org-truss-member-words sections)
                     '("Now" "Then" "Rain" "Umbrella")))
      (should (equal (mapcar (lambda (s) (org-truss-member-role s 'telling)) sections)
                     '(sky sky rain umbrella))))))

(ert-deftest org-truss-test-apply-pattern-keeps-a-nested-pattern ()
  "A section that takes a new one's place brings its own sections and pattern."
  (org-truss-test--with "* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Umbrella
:PROPERTIES:
:TRUSS_TELLING_ROLE: answer
:TRUSS_TELLING: sky-rain-umbrella
:END:
*** Sky
:PROPERTIES:
:TRUSS_TELLING_ROLE: sky
:END:
- [[truss-include:inner]]
"
    (org-truss-apply-telling (org-truss--part-pos "structure") 'scqa)
    (let* ((root (org-truss-model-structure (org-truss-read)))
           (answer (nth 3 (org-truss-member-supports root))))
      (should (equal (org-truss-member-words answer) "Umbrella"))
      (should (eq (org-truss-member-telling answer) 'sky-rain-umbrella))
      (should (equal (org-truss-member-includes (car (org-truss-member-supports answer)))
                     '("inner"))))))

(ert-deftest org-truss-test-add-places ()
  "A heading is put in for each role a pattern lacks, playing it in the
property of the pattern's kind."
  (org-truss-test--with org-truss-test--file
    (let ((move (org-truss-test--heading-pos "Move to fortnightly")))
      (should (= (org-truss-add-role-members move '((logic minor . 1))) 1))
      (should (string-match-p
               "^\\*\\*\\* Minor premise\n:PROPERTIES:\n:TRUSS_LOGIC_ROLE: minor\n:END:\n"
               (buffer-string)))
      (should-not (org-truss-gaps (org-truss-test--m (org-truss-read) "Move to fortnightly"))))))

(ert-deftest org-truss-test-unwrap ()
  "Unwrapping refuses to lose writing unless forced, and keeps every link.
The section's patterns go, of every kind, since what they asked was asked
of the sections taken away."
  (org-truss-test--with (replace-regexp-in-string "^- \\[\\[truss-include:half\\]\\]$"
                                                  "Why it drags.\n- [[truss-include:half]]"
                                                  org-truss-test--file)
    (let ((root (org-truss--part-pos "structure")))
      (should (equal (org-truss-unwrap root) '("Rain")))
      (should (= 3 (length (org-truss-member-supports
                            (org-truss-model-structure (org-truss-read))))))
      (org-truss-set-pattern root 'breakdown '5w1h)
      (should (null (org-truss-unwrap root t)))
      (let ((section (org-truss-model-structure (org-truss-read))))
        (should (null (org-truss-member-supports section)))
        (should (null (org-truss-member-patterns section)))
        (should (equal (org-truss-member-includes section)
                       '("long" "half" "move" "none")))))))

(ert-deftest org-truss-test-dissolve ()
  "A dissolved section hands its links to the section above."
  (org-truss-test--with org-truss-test--file
    (should (null (org-truss-dissolve (org-truss-test--heading-pos "Sky")
                                      (org-truss--part-pos "structure"))))
    (let ((root (org-truss-model-structure (org-truss-read))))
      (should (equal (org-truss-test--section-labels root) '("Rain" "Umbrella")))
      (should (equal (org-truss-member-includes root) '("long"))))))

(ert-deftest org-truss-test-links ()
  "Include links are added after the last one, moved, reordered and removed."
  (org-truss-test--with org-truss-test--file
    (let ((links-of (lambda (words)
                      (plist-get (org-truss--text-at (org-truss-test--heading-pos words)) :include-lines))))
      (org-truss-add-include (org-truss-test--heading-pos "Sky") "aside")
      (should (equal (funcall links-of "Sky") '("long" "aside")))
      (should (string-match-p "^- \\[\\[truss-include:long\\]\\]\n- \\[\\[truss-include:aside\\]\\]$"
                              (buffer-string)))
      (org-truss-shift-include (org-truss-test--heading-pos "Sky") "aside" -1)
      (should (equal (funcall links-of "Sky") '("aside" "long")))
      (org-truss-move-include (org-truss-test--heading-pos "Sky") "aside"
                           (org-truss-test--heading-pos "Rain"))
      (should (equal (funcall links-of "Sky") '("long")))
      (should (equal (funcall links-of "Rain") '("half" "aside")))
      (org-truss-remove-include (org-truss-test--heading-pos "Rain") "aside")
      (should (equal (funcall links-of "Rain") '("half"))))))

(ert-deftest org-truss-test-lead-line ()
  "A lead is written before the first line that tells a member, on an empty
line made for it, and is told before the members; with no such line there
is no place for one."
  (org-truss-test--with org-truss-test--file
    (let ((section (lambda (words)
                     (seq-find (lambda (s) (equal (org-truss-member-words s) words))
                               (org-truss-members-in (org-truss-read) 'structure)))))
      (goto-char (org-truss-lead-line (org-truss-test--heading-pos "Sky")))
      (should (looking-at "\n- \\[\\[truss-include:long"))
      (insert "Where we are.")
      (should (equal (org-truss-member-body (funcall section "Sky"))
                     "Where we are.\n- [[truss-include:long]]"))
      (should (string-match-p
               ":TRUSS_TELLING_ROLE: sky\n:END:\nWhere we are\\.\n- \\[\\[truss-include:long"
               (buffer-string)))
      (should-not (org-truss-lead-line (org-truss-test--heading-pos "Lone remark"))))))

(ert-deftest org-truss-test-add-include-to-an-empty-member ()
  "An include link added to a heading with nothing but a drawer goes under
the drawer."
  (org-truss-test--with "* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Empty
:PROPERTIES:
:TRUSS_TELLING_ROLE: ask
:END:
** Next
"
    (org-truss-add-include (org-truss-test--heading-pos "Empty") "A")
    (should (equal (plist-get (org-truss--text-at (org-truss-test--heading-pos "Empty")) :include-lines)
                   '("A")))
    (should (eq (org-truss-member-role
                 (car (org-truss-member-supports (org-truss-model-structure (org-truss-read))))
                 'telling)
                'ask))))

(ert-deftest org-truss-test-add-member ()
  "A new member goes last under the member above, with its roles."
  (org-truss-test--with org-truss-test--file
    (set-marker (org-truss-add-member (org-truss--part-pos "structure") "Ask" '((telling . ask))) nil)
    (let* ((root (org-truss-model-structure (org-truss-read)))
           (last (car (last (org-truss-member-supports root)))))
      (should (equal (org-truss-member-words last) "Ask"))
      (should (equal (org-truss-member-roles last) '((telling . ask)))))))

(ert-deftest org-truss-test-set-role ()
  "A heading's role in one kind of pattern is set, or taken off, apart from
its others."
  (org-truss-test--with org-truss-test--how-file
    (let ((pos (org-truss-test--heading-pos "As follows")))
      (org-truss-set-role pos 'telling 'body)
      (should (equal (org-truss-member-roles (org-truss-test--m (org-truss-read) "As follows"))
                     '((breakdown . how) (telling . body))))
      (org-truss-set-role pos 'breakdown nil)
      (should (equal (org-truss-member-roles (org-truss-test--m (org-truss-read) "As follows"))
                     '((telling . body)))))))

(ert-deftest org-truss-test-rename ()
  "Renaming a member changes its heading alone: links and grounds point to it
by its id, and still find it.  A label another member has is refused."
  (org-truss-test--with org-truss-test--file
    (let ((before (buffer-string)))
      (org-truss-rename (org-truss-test--heading-pos "Half the items repeat") "Agendas repeat")
      (should (equal (buffer-string)
                     (replace-regexp-in-string "^\\*\\* Half the items repeat$" "** Agendas repeat"
                                               before))))
    (let ((model (org-truss-read)))
      (should (equal (org-truss-member-words (org-truss-member-by-id model "half")) "Agendas repeat"))
      (should (equal (org-truss-member-grounds (org-truss-test--m model "Move to fortnightly"))
                     '("half"))))
    (org-truss-rename (org-truss-test--heading-pos "Agendas repeat") "Agendas repeat")
    (should-error (org-truss-rename (org-truss-test--heading-pos "Agendas repeat") "Lone remark")
                  :type 'user-error)))

(ert-deftest org-truss-test-rename-keeps-tags ()
  "A tagged member keeps its tags when relabelled."
  (org-truss-test--with org-truss-test--file
    (org-truss-rename (org-truss-test--heading-pos "Items need a week to move") "Items are slow")
    (should (org-truss-assumption-p (org-truss-test--m (org-truss-read) "Items are slow")))))

;;;; A new file

(ert-deftest org-truss-test-guides-read-as-text ()
  "No line of the guide starts the way Org syntax does -- a heading, a
drawer line, a block or a keyword but the example block it shows -- since
the guide sits in a drawer at the head of the file, and Org reads such a
line for what it looks like: with `org-hide-block-startup', a line opening
with #+begin_ and no block stops org-mode starting at all.  Nor does a
line of what a part or a role is for."
  (dolist (entry org-truss--part-guides)
    (dolist (text (cdr entry))
      (dolist (line (split-string text "\n"))
        (should-not (string-match-p "\\`[ \t]*\\(?:#\\+\\|\\*+ \\|:[[:alnum:]_-]+:[ \t]*\\'\\)"
                                    line)))))
  (dolist (org-truss-language '(en ja))
    (let ((example nil))
      (dolist (line (split-string (org-truss-guide) "\n"))
        (cond ((string-match-p "\\`[ \t]*#\\+begin_example\\'" line) (setq example t))
              ((string-match-p "\\`[ \t]*#\\+end_example\\'" line) (setq example nil))
              ((not example)
               (should-not (string-match-p "\\`[ \t]*\\(?:#\\+\\|\\*+ \\|:[[:alnum:]_-]+:[ \t]*\\'\\)"
                                           line)))))
      (should-not example)))
  ;; With a lead written under the structure, a #+begin_public opening a
  ;; guide's line would run to that lead's #+end_public.
  (dolist (org-truss-language '(en ja))
    (org-truss-test--with (concat (org-truss-skeleton "T")
                                  "#+begin_comment\nThe lead.\n#+end_comment\n")
      (org-fold-hide-block-all))))

(ert-deftest org-truss-test-guidance-shows-links-as-written ()
  "A link written in the comment block or a guide to show how one is written
is shown as written: Org draws a link there too, as its description alone,
unless it is code, ~[[#m7]]~, with a space either side."
  (dolist (org-truss-language '(en ja))
    (org-truss-test--with (org-truss-skeleton "T")
      (org-fold-show-all)
      (font-lock-ensure)
      (let ((n 0))
        (while (re-search-forward "\\[\\[#" nil t)
          (setq n (1+ n))
          (should-not (get-text-property (match-beginning 0) 'invisible)))
        (should (>= n 3))))))

(ert-deftest org-truss-test-guide-fits ()
  "No line of the guide runs past 80 columns but the commands, which are
copied, not read."
  (dolist (org-truss-language '(en ja))
    (dolist (line (split-string (apply #'org-truss--pick org-truss--guide-text) "\n"))
      (unless (string-match-p "emacs --batch" line)
        (should (<= (string-width line) 80))))))

(ert-deftest org-truss-test-skeleton ()
  "A new file has its parts and members for their roles, their words in
English whatever the language: facts in Subject, what they mean and what
to do in Message, and Structure telling them in that order, each heading
that member there.  End members are items.  The guide is in the
language, in a drawer at its head, and only there.  Its first line keeps
what is attached to its headings beside it, and the guide names the
directories there."
  (dolist (org-truss-language '(en ja))
    (org-truss-test--with (org-truss-skeleton "T")
      (let ((model (org-truss-read)))
        (should (equal (org-truss-model-title model) "T"))
        (should (string-prefix-p (concat "# -*- org-attach-id-dir: \"attach/\"; -*-\n"
                                         "#+title: T\n\n:GUIDE:\n" (org-truss-guide) ":END:\n\n* Brief\n")
                                 (buffer-string)))
        (should (equal (hack-local-variables-prop-line) '((org-attach-id-dir . "attach/"))))
        (dolist (dir '("^  sources/ " "^  notes/ " "^  attach/ " "^  out/ "))
          (should (string-match-p dir (buffer-string))))
        (should (equal (org-map-entries (lambda () (org-get-heading t t t t)))
                       '("Brief" "Subject" "Part" "Message" "Interpretation" "Part" "Action"
                         "Structure" "[[truss-include:m1]]" "[[truss-include:m2]]"
                         "[[truss-include:m3]]")))
        (should (string-match-p (if (eq org-truss-language 'ja)
                                    "^:GUIDE:\nこの truss\\.org から出力文書を一つ作る。"
                                  "^:GUIDE:\nThis truss\\.org makes one output document\\.")
                                (buffer-string)))
        (should (= (how-many "^:GUIDE:$" (point-min) (point-max)) 1))
        (should (string-match-p ":TRUSS_BREAKDOWN: reader-question-response-constraints\n"
                                (buffer-string)))
        (should (eq (org-truss-member-breakdown (org-truss-model-brief model))
                    'reader-question-response-constraints))
        (should (eq (org-truss-member-breakdown (org-truss-model-subject model)) 'parts))
        (should (eq (org-truss-member-breakdown (org-truss-model-message model))
                    'interpretation-action))
        (should-not (plist-get (org-truss-checks model) :no-relation))
        (should (equal (mapcar #'car (org-truss-test--fields (org-truss-model-brief model)))
                       '(((breakdown . reader)) ((breakdown . question))
                         ((breakdown . response)) ((breakdown . constraints)))))
        (should (seq-every-p #'org-truss-item-p
                             (org-truss-member-supports (org-truss-model-brief model))))
        (should (seq-every-p (lambda (f) (string-empty-p (cdr f)))
                             (org-truss-test--fields (org-truss-model-brief model))))
        (let ((source (car (org-truss-member-supports (org-truss-model-subject model)))))
          (should (eq (org-truss-member-breakdown source) 'parts))
          (should (seq-every-p #'org-truss-item-p (org-truss-member-supports source))))
        (pcase-let ((`(,interpretation ,action) (org-truss-message-supports model)))
          (should (equal (org-truss-member-roles interpretation) '((breakdown . interpretation))))
          (should (eq (org-truss-member-breakdown interpretation) 'parts))
          (should (eq (org-truss-member-logic (car (org-truss-member-supports interpretation)))
                      'reasons))
          (should (equal (org-truss-member-roles action) '((breakdown . action))))
          (should (eq (org-truss-member-breakdown action) 'steps))
          (should (seq-every-p #'org-truss-item-p (org-truss-member-supports action)))
          (let ((structure (org-truss-model-structure model)))
            (should (eq (org-truss-member-pattern structure 'telling) 'sky-rain-umbrella))
            (should (equal (mapcar #'org-truss-member-includes (org-truss-member-supports structure))
                           '(("m1") ("m2") ("m3"))))
            (should (equal (mapcar (lambda (id) (org-truss-member-by-id model id)) '("m1" "m2" "m3"))
                           (list (org-truss-model-subject model) interpretation action)))))
        (let ((checks (org-truss-checks model)))
          (should-not (plist-get checks :gaps))
          (should-not (plist-get checks :no-role))
          (should-not (plist-get checks :out-of-order))
          (should-not (plist-get checks :broken-links)))))))

(ert-deftest org-truss-test-add-place ()
  "A member put in for a role goes where the pattern lists it among the
headings there, under any heading, with no guide of its own: the board
says what it is for."
  (org-truss-test--with org-truss-test--conditions-file
    (set-marker (org-truss-add-role-member (org-truss--part-pos "brief") 'breakdown 'constraints) nil)
    (set-marker (org-truss-add-role-member (org-truss--part-pos "subject") 'breakdown 'past) nil)
    (let ((model (org-truss-read)))
      (should (equal (mapcar #'org-truss-member-words (org-truss-member-supports (org-truss-model-brief model)))
                     '("Reader" "Their question" "Response wanted" "Constraints")))
      (should (equal (mapcar #'org-truss-member-words (org-truss-member-supports (org-truss-model-subject model)))
                     '("Past" "Issue" "Constraints")))
      (should-not (string-match-p ":GUIDE:" (buffer-string)))
      (should-not (plist-get (org-truss-checks model) :gaps)))))

(ert-deftest org-truss-test-refresh-guides ()
  "Refreshing puts the current guide in its drawer at the head, in place of
a guide before it -- a drawer, or the comments it was once written in --
and takes away the guides once written under the parts and the members
playing their roles.  A guide of your own, of a role nothing is said of
or of any other member, stays, and so does what is written before the
first heading that is no comment.  A file without the first line that
keeps its attachments beside it is given it, and the buffer takes it at
once."
  (let ((org-truss-language 'ja))
    (org-truss-test--with "#+title: T

# An old preamble.
:GUIDE:
An old guide.
:END:
Notes before the parts.

* 与件
:PROPERTIES:
:TRUSS_PART: brief
:TRUSS_BREAKDOWN: reader-question-response-constraints
:END:
:GUIDE:
Old wording.
:END:
Notes on the brief.
** Reader
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: reader
:END:
:GUIDE:
Old reader.
:END:
The board.
** Mine
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: mine
:END:
:GUIDE:
My own.
:END:

* Message
:PROPERTIES:
:TRUSS_PART: message
:END:
:GUIDE:
Old message.
:END:
** A member
:GUIDE:
Not a part's.
:END:
"
      (org-truss-refresh-guides-in-buffer)
      (let ((text (buffer-string)))
        (should (string-prefix-p (concat "# -*- org-attach-id-dir: \"attach/\"; -*-\n"
                                         "#+title: T\n\n:GUIDE:\n" (org-truss-guide) ":END:\n\n"
                                         "Notes before the parts.\n\n* 与件\n")
                                 text))
        (should (equal org-attach-id-dir "attach/"))
        (should-not (string-match-p "Old wording\\|Old reader\\|Old message\\|An old preamble\\|An old guide" text))
        (should (string-match-p (concat ":TRUSS_BREAKDOWN: reader-question-response-constraints\n"
                                        ":END:\nNotes on the brief\\.")
                                text))
        (should (string-match-p ":TRUSS_BREAKDOWN_ROLE: reader\n:END:\nThe board\\." text))
        (should (string-match-p ":TRUSS_BREAKDOWN_ROLE: mine\n:END:\n:GUIDE:\nMy own\\." text))
        (should (string-match-p ":GUIDE:\nNot a part's\\.\n:END:" text))
        (org-truss-refresh-guides-in-buffer)
        (should (equal (buffer-string) text))))))

(ert-deftest org-truss-test-guide-of ()
  "What a line is for: a part's guide, a role's of Brief's or Subject's
breakdown on the member playing it, and for any other member its patterns
and the roles it plays."
  (let ((org-truss-language 'en))
    (org-truss-test--with org-truss-test--conditions-file
      (let ((model (org-truss-read)))
        (should (string-prefix-p "What the output document must satisfy."
                                 (org-truss-guide-of model (org-truss-model-brief model))))
        (should (equal (org-truss-guide-of model (car (org-truss-member-supports (org-truss-model-brief model))))
                       "Who reads it, and what do they already know?"))))
    (org-truss-test--with org-truss-test--file
      (let ((model (org-truss-read)))
        (should (equal (org-truss-guide-of model (org-truss-test--m model "Half the items repeat"))
                       "logic › reasons: reasons that each hold it up alone"))))))

(ert-deftest org-truss-test-new-ids-pass-the-guide ()
  "The next ID free is counted from the first heading: the guide's
examples, <<m21>> among them, are no member's."
  (org-truss-test--with (concat (org-truss-skeleton "T") "\n** A\n:PROPERTIES:\n:CUSTOM_ID: m8\n:END:\n")
    (should (equal (org-truss--next-id) "m9"))))

(ert-deftest org-truss-test-file-variables ()
  "A first line setting variables of its own gets the attachments' among
them; one that sets where attachments go already is left as it is."
  (org-truss-test--with "# -*- fill-column: 70 -*-\n#+title: T\n"
    (org-truss-put-file-variables)
    (let ((vars (hack-local-variables-prop-line)))
      (should (equal (alist-get 'fill-column vars) 70))
      (should (equal (alist-get 'org-attach-id-dir vars) "attach/")))
    (should (string-match-p "\n#\\+title: T\n\\'" (buffer-string))))
  (org-truss-test--with "# -*- org-attach-id-dir: \"pictures/\" -*-\n#+title: T\n"
    (let ((before (buffer-string)))
      (org-truss-put-file-variables)
      (should (equal (buffer-string) before)))))

(provide 'org-truss-core-test)

;;; org-truss-core-test.el ends here

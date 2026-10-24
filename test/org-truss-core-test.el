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

* Members
:PROPERTIES:
:TRUSS_PART: members
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
:TRUSS_BREAKDOWN: premises-issue-constraints
:END:
** Issue
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: issue
:END:
*** Nobody checks before a test
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: constraints
:END:
Finance said so at the October meeting.
*** No budget this year
:PROPERTIES:
:CUSTOM_ID: budget
:END:
# [[https://e.x/finance-3-october][finance, 3 October]]
*** The schedule is fixed

* Members
:PROPERTIES:
:TRUSS_PART: members
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
:TRUSS_BREAKDOWN: premises-issue-constraints
:END:
** Premises
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: premises
:END:
*** How many cars we run
** Constraints
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: constraints
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

* Members
:PROPERTIES:
:TRUSS_PART: members
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

* Members
:PROPERTIES:
:TRUSS_PART: members
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

* Members
:PROPERTIES:
:TRUSS_PART: members
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
* Members
:PROPERTIES:
:TRUSS_PART: members
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
:TRUSS_PART: members
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
  (mapcar #'org-truss-member-label members))

(defun org-truss-test--m (model label)
  (or (org-truss-member-by-label model label)
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
  (mapcar #'org-truss-section-label (org-truss-section-children section)))

(defun org-truss-test--cluster-labels (clusters)
  (mapcar #'org-truss-cluster-label clusters))

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
      (should (eq (org-truss-cluster-role follows 'breakdown) 'how))
      (should (eq (org-truss-member-breakdown follows) 'steps))
      (should (equal (org-truss-gaps check) '((breakdown what . 1) (breakdown why . 1))))
      (should-not (org-truss-gaps follows))
      (should (equal (org-truss-kind-roles safer 'telling) '(point reason example recap)))
      (should (equal (org-truss-gaps safer) '((telling point . 1) (telling recap . 1))))
      (should-not (org-truss-no-role check))
      (should (equal (mapcar (lambda (o) (cons (org-truss-member-label (car o))
                                               (org-truss-member-label (cdr o))))
                             (plist-get (org-truss-checks model) :out-of-order))
                     '(("Alcohol slows reactions" . "A drunk driver crashed last year"))))))
  (org-truss-test--with (replace-regexp-in-string
                         ":TRUSS_TELLING: prep" ":TRUSS_LOGIC: deduction\n:TRUSS_TELLING: prep"
                         org-truss-test--how-file)
    (let ((member (org-truss-test--m (org-truss-read) "Tests are safer checked")))
      (should (equal (org-truss-gaps member) '((logic major . 1) (logic minor . 1)
                                               (telling point . 1) (telling recap . 1))))
      (should (equal (mapcar (lambda (hit) (cons (org-truss-member-label (car hit)) (cdr hit)))
                             (org-truss-no-role member))
                     '(("A drunk driver crashed last year" . logic)
                       ("Alcohol slows reactions" . logic)))))))

(ert-deftest org-truss-test-induction-wants-two-cases ()
  "A role a pattern wants more of is short by as many as are missing."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
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
      (should (equal (mapcar (lambda (hit) (list (org-truss-cluster-label (car hit)) (cadr hit)
                                                 (org-truss-cluster-label (cddr hit))))
                             hits)
                     '(("Example" telling "Move to fortnightly")
                       ("Notes for later" telling "Structure"))))))
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
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
:TRUSS_PART: members
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
      (should (equal (mapcar (lambda (hit) (list (org-truss-cluster-label (car hit)) (cadr hit)
                                                 (org-truss-cluster-label (cddr hit))))
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
:TRUSS_PART: members
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
           (what (cadr (org-truss-section-children root)))
           (move (org-truss-test--m model "We move to fortnightly reviews")))
      (should (equal (org-truss-gaps root) '((telling complication . 1) (telling question . 1))))
      (should (eq (org-truss-section-logic what) 'reasons))
      (should (equal (mapcar #'cadr (org-truss-gaps what)) '(reason who when where what how)))
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
      (should (eq (org-truss-role-label-under check (org-truss-test--m model "The driver's manager"))
                  'who))
      (should (eq (org-truss-list-form (org-truss-test--m model "As follows")) 'numbered))
      (should (eq (org-truss-list-form needs) 'bulleted))
      (should-not (org-truss-role-label-under needs (org-truss-test--m model "Someone to check")))
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
      (should (equal (mapcar (lambda (o) (cons (org-truss-section-label (car o))
                                               (org-truss-section-label (cdr o))))
                             late)
                     '(("空" . "Rain"))))))
  (should (string-match-p
           "Out of order --.*\n.*: 空 -- below Rain, which TRUSS_TELLING tells after it"
           (org-truss-test--with org-truss-test--unfinished-file
             (org-truss-check-report (org-truss-read) "truss.org")))))

;;;; Grounds

(defconst org-truss-test--grounds-file "* M
:PROPERTIES:
:TRUSS_PART: members
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
      (should (equal (org-truss-cluster-refs (funcall m "Through a bare one")) '("bare" "fact")))
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
      (should (equal (mapcar (lambda (w) (cons (org-truss-member-label (car w)) (cdr w)))
                             (plist-get (org-truss-checks model) :weak-grounds))
                     '(("Through a bare one" . "bare") ("Points at a bare one" . "bare")))))))

(ert-deftest org-truss-test-grounds-in-the-text ()
  "A link in a heading's text to a member is grounds: it gives the heading
grounds, and what it points to must hold and be there.  A section reads
its text alike, and a section with a logic asks grounds of its reasons as
a member does: a reason stands on what it tells, an item listing a member
too."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
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
           (section (lambda (label)
                      (seq-find (lambda (s) (equal (org-truss-section-label s) label))
                                (org-truss-sections model))))
           (pairs (lambda (key)
                    (mapcar (lambda (hit) (cons (org-truss-cluster-label (car hit)) (cdr hit)))
                            (plist-get checks key)))))
      (should (equal (org-truss-cluster-text-grounds (org-truss-test--m model "Cites a fact")) '("fact")))
      (should (org-truss-has-grounds-p (org-truss-test--m model "Cites a fact")))
      (should (equal (funcall pairs :weak-grounds) '(("Cites a bare one" . "bare") ("Because" . "bare"))))
      (should (equal (funcall pairs :broken-grounds) '(("Cites nothing there" . "gone"))))
      (should-not (org-truss-cluster-text-grounds (funcall section "Why")))
      (should (equal (org-truss-cluster-refs (funcall section "Why")) '("fact")))
      (should (equal (org-truss-cluster-refs (funcall section "Because")) '("bare" "fact")))
      (should-not (plist-get checks :no-grounds)))))

(ert-deftest org-truss-test-reason-told-on-its-line ()
  "A reason whose heading's line tells a member is that member there, and
stands on it: it has grounds, weak when the member does not hold.  Under
a breakdown, or in a section's text, such a link tells and is no ground."
  (org-truss-test--with "* M
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
      (should (equal (mapcar #'org-truss-cluster-refs (org-truss-cluster-children claim))
                     '(("fact") ("bare"))))
      (should-not (plist-get checks :no-grounds))
      (should (equal (mapcar (lambda (w) (cons (org-truss-cluster-label (car w)) (cdr w)))
                             (plist-get checks :weak-grounds))
                     '(("[[truss-include:bare]]" . "bare"))))
      (should-not (org-truss-cluster-refs (car (org-truss-cluster-children split)))))))

(ert-deftest org-truss-test-mixed-sources ()
  "The parts with nothing under them keep to one source, wherever they are,
and a logic of the subject keeps to one in all it holds.  One taken by
org-moor is one source wherever its links point and whatever they say;
a part with parts under it is one source of its own; links to members
are no sources; a logic of the members brings sources together."
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
:TRUSS_PART: members
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
      (should (equal (mapcar (lambda (m) (cons (org-truss-cluster-label (car m)) (cdr m)))
                             (plist-get (org-truss-checks model) :mixed-sources))
                     '(("Mixed" "moor:form" "https://e.x/page")
                       ("Summed up" "moor:rule" "notes/memo.org"))))
      (should (string-match-p "^Mixed sources -- .*\n.*:[0-9]+: Mixed -- points into moor:form, https://e.x/page$"
                              (org-truss-check-report model))))))

(defconst org-truss-test--includes-file "* M
:PROPERTIES:
:TRUSS_PART: members
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
           (pairs (lambda (key) (mapcar (lambda (hit) (cons (org-truss-cluster-label (car hit)) (cdr hit)))
                                        (plist-get checks key)))))
      (should (equal (org-truss-cluster-includes move) '("long" "loop")))
      (should-not (org-truss-cluster-text-grounds move))
      (should (equal (org-truss-test--labels (org-truss-told model))
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
:TRUSS_PART: members
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
          (should (equal (mapcar (lambda (b) (cons (org-truss-member-label (car b)) (cdr b))) broken)
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
      (should-not (string-match-p "aside" (or (org-truss-cluster-body
                                               (org-truss-test--m (org-truss-read) "Half the items repeat"))
                                              "")))
      (should (equal (org-truss-cluster-refs (org-truss-test--m (org-truss-read) "Half the items repeat"))
                     '("long" "diff" "aside")))
      (should (org-truss-remove-ground half "aside"))
      (should (org-truss-remove-ground half "long"))
      (should-not (org-truss-remove-ground half "diff"))
      (should (equal (org-truss-cluster-refs (org-truss-test--m (org-truss-read) "Half the items repeat"))
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
      (should (equal (mapcar (lambda (g) (cons (org-truss-cluster-label (car g)) (cdr g)))
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
      (should (equal (mapcar (lambda (b) (cons (org-truss-member-label (car b)) (cdr b)))
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
:TRUSS_PART: members
:END:
"
    (should (equal (org-truss-check-report (org-truss-read) "f") "Nothing is left to do.\n"))))

(ert-deftest org-truss-test-told ()
  "The document tells what its sections list, with what is nested under it."
  (org-truss-test--with org-truss-test--file
    (should (equal (org-truss-test--labels (org-truss-told (org-truss-read)))
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
:TRUSS_PART: members
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
      (should (equal (org-truss-member-label (org-truss-heading-by-ref model "x")) "One"))
      (should (string-match-p "^f:[0-9]+: Two -- #x, which another heading has too$"
                              (org-truss-check-report model "f")))
      (should (string-match-p "^f:[0-9]+: Three -- #x, which another heading has too$"
                              (org-truss-check-report model "f"))))))

;;;; Reading

(ert-deftest org-truss-test-own-text ()
  "A link pointing to a member in the text, in a comment or in what the
reader is told, is a reference; one in a drawer is not.  Nor is a link
that tells a member.  The reader is told the text outside the comments; a
# in a block is no comment."
  (org-truss-test--with org-truss-test--file
    (let ((own (org-truss--own (org-truss-test--heading-pos "Half the items repeat"))))
      (should (equal (org-truss--refs-in (org-truss--text own)) '("long" "diff" "long")))
      (should-not (plist-get own :includes))
      (should (equal (plist-get (org-truss--own (org-truss-test--heading-pos "Sky")) :includes)
                     '("long")))
      (should (equal (plist-get own :body)
                     "Half of each agenda repeats the week before, as [[#long]] shows.\n"))
      (should (equal (plist-get own :comments)
                     "[[#long]]\nRobin keeps raising the same items; see [[#diff]].\n")))
    (org-truss-test--with "* H\nTold.\n#+begin_comment\nKept, [[#a]].\n#+end_comment\n#+begin_src sh\n# told too\n#+end_src\n#\n"
      (let ((own (org-truss--own (point-min))))
        (should (equal (plist-get own :body) "Told.\n#+begin_src sh\n# told too\n#+end_src\n"))
        (should (equal (plist-get own :comments) "Kept, [[#a]].\n\n"))
        (should (equal (org-truss--refs-in (org-truss--text own)) '("a")))))
    (let ((own (org-truss--own (org-truss-test--heading-pos "Half the items repeat"))))
      (should (equal (plist-get own :props) '(("CUSTOM_ID" . "half")
                                              ("TRUSS_LOGIC" . "reasons")))))))

(ert-deftest org-truss-test-references ()
  "A link or a ground points to a member by its CUSTOM_ID, and a link that
tells one names it by its CUSTOM_ID too.  One that names a heading points
to no member, and shows as broken."
  (should (equal (org-truss--refs-in "[[#a]] and [[#b][words]], [[*C]] [[https://x]] [[truss-include:d]]")
                 '("a" "b" "*C")))
  (should (equal (org-truss--includes-in "[[truss-include:d]] [[#a]] [[truss-include:e][E]]")
                 '("d" "e")))
  (should (equal (org-truss--link-item "a") "- [[truss-include:a]]\n"))
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-member-label (org-truss-heading-by-ref model "half"))
                     "Half the items repeat"))
      (should (equal (org-truss-member-id (org-truss-test--m model "Lone remark")) nil))
      (should-not (org-truss-heading-by-ref model "Half the items repeat")))))

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
* Members
:PROPERTIES:
:TRUSS_PART: members
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
           (less (org-truss-heading-by-ref model "m21"))
           (wait (org-truss-test--m model "Items wait longer"))
           (likes (org-truss-test--m model "人 :: Robin likes it, as [[m21]] says")))
      (should (eq (org-truss-member-logic move) 'reasons))
      (should (eq (org-truss-member-breakdown move) 'pros-cons))
      (should (equal (org-truss-member-body move) "We would meet half as often.\n\nAfter the list."))
      (should (equal (org-truss-test--labels (org-truss-member-children move))
                     '("Less time in meetings" "Items wait longer"
                       "人 :: Robin likes it, as [[m21]] says" "A heading under it too")))
      (should (equal (org-truss-member-label less) "Less time in meetings"))
      (should (equal (org-truss-member-roles less) '((logic . reason) (breakdown . pros))))
      (should (equal (org-truss-member-roles likes) '((logic . reason))))
      (should (equal (org-truss-member-body less) "An hour a fortnight back."))
      (should (equal (org-truss-member-notes less) "[[#m2]]"))
      (should (equal (org-truss-cluster-refs less) '("m2")))
      (should (equal (org-truss-cluster-refs likes) '("m21")))
      (should (= (org-truss-member-holder less) (org-truss-member-pos move)))
      (should (= (org-truss-member-level less) 3))
      (should (eq (org-truss-member-breakdown wait) 'steps))
      (should (equal (mapcar #'org-truss-member-roles (org-truss-member-children wait))
                     '(((breakdown . step)) ((breakdown . step)))))
      (should (eq (org-truss-parent model less) move))
      (let ((checks (org-truss-checks model)))
        (should (equal (org-truss-test--labels (plist-get checks :no-grounds))
                       '("Items wait longer")))
        (should (equal (mapcar (lambda (hit) (org-truss-member-label (car hit))) (plist-get checks :no-role))
                       '("A heading under it too" "人 :: Robin likes it, as [[m21]] says"
                         "A heading under it too")))))))

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
      (should (equal (org-truss-cluster-refs (org-truss-test--m (org-truss-read) "Six of twelve items come back"))
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
          (org-truss-part-children part)))

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
                     '((((breakdown . issue)) . "")
                       (((breakdown . constraints)) . "Finance said so at the October meeting."))))
      (should (equal (org-truss-test--labels
                      (org-truss-member-children (cadr (org-truss-part-children subject))))
                     '("No budget this year" "The schedule is fixed")))
      (should (eq (org-truss-parent model (org-truss-test--m model "The schedule is fixed"))
                  (cadr (org-truss-part-children subject))))
      (should (eq (org-truss-parent model (cadr (org-truss-part-children subject))) subject))
      (should (equal (plist-get (org-truss-checks model) :gaps)
                     (list (cons (org-truss-model-brief model) '((breakdown constraints . 1)))
                           (cons subject '((breakdown premises . 1))))))
      (should (eq (org-truss-cluster-at model (org-truss-part-pos subject)) subject))
      (should (eq (org-truss-member-home (org-truss-test--m model "No budget this year")) 'subject))
      (should (equal (org-truss-test--labels (org-truss-told model)) '("No budget this year")))
      (should (equal (org-truss-test--labels (org-truss-model-all model))
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
      (should (eq (org-truss-member-home head) 'subject))
      (should (eq (org-truss-member-home (org-truss-test--m model "The rule may apply to us")) 'members))
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
      (should-not (org-truss-cluster-patterns head))
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
      (should (equal (org-truss-cluster-refs check) '("law")))
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
* Members
:PROPERTIES:
:TRUSS_PART: members
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
                   (claim (org-truss-member-by-label model "A claim")))
              (should (equal (org-truss-member-body claim)
                             "[[file:attach/ab/cdef/shot.png]]"))
              (should (equal (org-truss-member-notes claim)
                             "See [[file:attach/ab/cdef/shot.png][the shot]]."))
              (should (equal (org-truss-member-body (org-truss-member-by-label model "Another"))
                             "[[attachment:shot.png]]"))
              (should (string-match-p "^\\[\\[attachment:shot\\.png\\]\\]\n# See"
                                      (buffer-string))))
          (kill-buffer))))))

;;;; Editing the structure

(ert-deftest org-truss-test-convert-references ()
  "Links and grounds that name headings come to point by id, the member
named being given one, and the words beside stay; a heading no member
has stays, broken."
  (org-truss-test--with (replace-regexp-in-string
                         "^- \\[\\[truss-include:\\(long\\|half\\)\\]"
                         (lambda (m) (if (equal (match-string 1 m) "long")
                                         "- [[truss-include:*Reviews run long]"
                                       "- [[truss-include:*Half the items repeat]"))
                         (replace-regexp-in-string
                          "^# \\[\\[#half\\]\\]$"
                          "# [[*Half the items repeat]] [[*Lone remark]] [[*Nobody]] the agendas"
                          (replace-regexp-in-string ":CUSTOM_ID: half\n" "" org-truss-test--file)))
    (should (= (org-truss-convert-references-in-buffer) 4))
    (let* ((model (org-truss-read))
           (lone (org-truss-member-id (org-truss-test--m model "Lone remark")))
           (half (org-truss-member-id (org-truss-test--m model "Half the items repeat")))
           (move (org-truss-test--m model "Move to fortnightly")))
      (should (equal (list half lone) '("m1" "m2")))
      (should (equal (org-truss-cluster-refs move) '("m1" "m2" "*Nobody")))
      (should (string-match-p "^# \\[\\[#m1\\]\\] \\[\\[#m2\\]\\] \\[\\[\\*Nobody\\]\\] the agendas$"
                              (buffer-string)))
      (should (equal (org-truss-cluster-refs (org-truss-test--m model "Half the items repeat"))
                     '("long" "diff")))
      (should (equal (org-truss-cluster-includes (car (org-truss-section-children
                                                    (org-truss-model-structure model))))
                     '("long")))
      (should (string-match-p "^- \\[\\[truss-include:m1\\]\\]$" (buffer-string)))
      (should (string-match-p "as \\[\\[#long\\]\\] shows" (buffer-string))))
    (should (= (org-truss-convert-references-in-buffer) 0))))

(ert-deftest org-truss-test-convert-grounds ()
  "What TRUSS_GROUNDS said goes into the text, after what is there: each
link on a line of its own, the words after them.  A heading the
words alone grounded is taken as given."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Claim
:PROPERTIES:
:TRUSS_LOGIC: reasons
:END:
*** Linked
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: [[#fact]] [[moor:6f1c::3][Minutes l. 3]] the agendas
:END:
Said so.
*** Agreed
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: team agreement
:END:
*** Quoted
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: the minutes
:END:
#+begin_quote
We agreed.
#+end_quote
** Fact
:PROPERTIES:
:CUSTOM_ID: fact
:END:
"
    (should (= (org-truss-convert-grounds-in-buffer) 3))
    (should-not (string-search "TRUSS_GROUNDS" (buffer-string)))
    (should (string-search (concat "Said so.\n[[#fact]]\n[[moor:6f1c::3][Minutes l. 3]]\n"
                                   "the agendas\n*** Agreed")
                           (buffer-string)))
    (let ((model (org-truss-read)))
      (should (org-truss-assumption-p (org-truss-test--m model "Agreed")))
      (should-not (org-truss-assumption-p (org-truss-test--m model "Linked")))
      (should-not (org-truss-assumption-p (org-truss-test--m model "Quoted")))
      (should-not (plist-get (org-truss-checks model) :no-grounds)))
    (should (= (org-truss-convert-grounds-in-buffer) 0))))

(ert-deftest org-truss-test-apply-section-telling ()
  "A section takes the place of the one new section whose telling role it
plays, as it is; the pattern adds the rest, and what fits no place stays
at the end."
  (org-truss-test--with (replace-regexp-in-string
                         ":TRUSS_TELLING_ROLE: umbrella" ":TRUSS_TELLING_ROLE: answer"
                         (replace-regexp-in-string ":TRUSS_TELLING_ROLE: sky" ":TRUSS_TELLING_ROLE: situation"
                                                   org-truss-test--file))
    (org-truss-apply-section-telling (org-truss--part-pos "structure") 'scqa)
    (let* ((model (org-truss-read))
           (root (org-truss-model-structure model))
           (by-label (lambda (l) (seq-find (lambda (s) (equal (org-truss-section-label s) l))
                                           (org-truss-section-children root)))))
      (should (eq (org-truss-section-telling root) 'scqa))
      (should (equal (org-truss-test--section-labels root)
                     '("Sky" "Complication" "Question" "Umbrella" "Rain")))
      (should (equal (org-truss-cluster-includes (funcall by-label "Sky"))
                     '("long")))
      (should (equal (org-truss-cluster-includes (funcall by-label "Umbrella"))
                     '("move" "none")))
      (should (eq (org-truss-cluster-role (funcall by-label "Umbrella") 'telling) 'answer))
      (should (eq (org-truss-cluster-role (funcall by-label "Question") 'telling) 'question))
      (should (string-match-p "^\\*\\* Question\n:PROPERTIES:\n:TRUSS_TELLING_ROLE: question\n:END:"
                              (buffer-string)))
      (should (equal (org-truss-cluster-includes (funcall by-label "Rain"))
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
    (org-truss-apply-section-telling (org-truss--part-pos "structure") 'sky-rain-umbrella)
    (let ((sections (org-truss-section-children (org-truss-model-structure (org-truss-read)))))
      (should (equal (mapcar #'org-truss-section-label sections)
                     '("Now" "Then" "Rain" "Umbrella")))
      (should (equal (mapcar (lambda (s) (org-truss-cluster-role s 'telling)) sections)
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
    (org-truss-apply-section-telling (org-truss--part-pos "structure") 'scqa)
    (let* ((root (org-truss-model-structure (org-truss-read)))
           (answer (nth 3 (org-truss-section-children root))))
      (should (equal (org-truss-section-label answer) "Umbrella"))
      (should (eq (org-truss-section-telling answer) 'sky-rain-umbrella))
      (should (equal (org-truss-cluster-includes (car (org-truss-section-children answer)))
                     '("inner"))))))

(ert-deftest org-truss-test-add-places ()
  "A heading is put in for each role a pattern lacks, playing it in the
property of the pattern's kind."
  (org-truss-test--with org-truss-test--file
    (let ((move (org-truss-test--heading-pos "Move to fortnightly")))
      (should (= (org-truss-add-places move '((logic minor . 1))) 1))
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
      (should (= 3 (length (org-truss-section-children
                            (org-truss-model-structure (org-truss-read))))))
      (org-truss-set-pattern root 'breakdown '5w1h)
      (should (null (org-truss-unwrap root t)))
      (let ((section (org-truss-model-structure (org-truss-read))))
        (should (null (org-truss-section-children section)))
        (should (null (org-truss-cluster-patterns section)))
        (should (equal (org-truss-cluster-includes section)
                       '("long" "half" "move" "none")))))))

(ert-deftest org-truss-test-dissolve ()
  "A dissolved section hands its links to the section above."
  (org-truss-test--with org-truss-test--file
    (should (null (org-truss-dissolve (org-truss-test--heading-pos "Sky")
                                      (org-truss--part-pos "structure"))))
    (let ((root (org-truss-model-structure (org-truss-read))))
      (should (equal (org-truss-test--section-labels root) '("Rain" "Umbrella")))
      (should (equal (org-truss-cluster-includes root) '("long"))))))

(ert-deftest org-truss-test-links ()
  "Links are added after the last one, moved, reordered and removed."
  (org-truss-test--with org-truss-test--file
    (let ((links-of (lambda (label)
                      (plist-get (org-truss--own (org-truss-test--heading-pos label)) :items))))
      (org-truss-add-link (org-truss-test--heading-pos "Sky") "aside")
      (should (equal (funcall links-of "Sky") '("long" "aside")))
      (should (string-match-p "^- \\[\\[truss-include:long\\]\\]\n- \\[\\[truss-include:aside\\]\\]$"
                              (buffer-string)))
      (org-truss-shift-link (org-truss-test--heading-pos "Sky") "aside" -1)
      (should (equal (funcall links-of "Sky") '("aside" "long")))
      (org-truss-move-link (org-truss-test--heading-pos "Sky") "aside"
                           (org-truss-test--heading-pos "Rain"))
      (should (equal (funcall links-of "Sky") '("long")))
      (should (equal (funcall links-of "Rain") '("half" "aside")))
      (org-truss-remove-link (org-truss-test--heading-pos "Rain") "aside")
      (should (equal (funcall links-of "Rain") '("half"))))))

(ert-deftest org-truss-test-lead-line ()
  "A lead is written before the first line that tells a member, on an empty
line made for it, and is told before the members; with no such line there
is no place for one."
  (org-truss-test--with org-truss-test--file
    (let ((section (lambda (label)
                     (seq-find (lambda (s) (equal (org-truss-section-label s) label))
                               (org-truss-sections (org-truss-read))))))
      (goto-char (org-truss-lead-line (org-truss-test--heading-pos "Sky")))
      (should (looking-at "\n- \\[\\[truss-include:long"))
      (insert "Where we are.")
      (should (equal (org-truss-section-body (funcall section "Sky"))
                     "Where we are.\n- [[truss-include:long]]"))
      (should (string-match-p
               ":TRUSS_TELLING_ROLE: sky\n:END:\nWhere we are\\.\n- \\[\\[truss-include:long"
               (buffer-string)))
      (should-not (org-truss-lead-line (org-truss-test--heading-pos "Lone remark"))))))

(ert-deftest org-truss-test-convert-public ()
  "A file written with public blocks comes to be told by the text under its
headings: what was outside a public block goes into a comment block, the
block's text becomes the text, a title other than the heading is kept on
a comment line, and the lines telling members follow -- a link in a
sentence there as an item of its own.  A file with no public block is
written as it is now, and is left alone: done again, it changes nothing."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Half the items repeat
:PROPERTIES:
:CUSTOM_ID: half
:END:
[[#long]]
Robin said so, as [[truss-include:long]] shows.
#+begin_public Most items come back
Half of each agenda repeats.
#+end_public
- [[truss-include:diff]]

** Already a comment
# Only this.
** Plain
Kept for me.
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
#+begin_public Now
The lead.
#+end_public
- [[truss-include:half]]
"
    (should (= (org-truss-convert-public-in-buffer) 3))
    (should (string-search "** Half the items repeat
:PROPERTIES:
:CUSTOM_ID: half
:END:
#+begin_comment
[[#long]]
Robin said so, as [[truss-include:long]] shows.
#+end_comment

# Title for the reader: Most items come back
Half of each agenda repeats.

- [[truss-include:long]]
- [[truss-include:diff]]

** Already a comment
# Only this.
** Plain
#+begin_comment
Kept for me.
#+end_comment
* S" (buffer-string)))
    (should (string-search "** Now
The lead.

- [[truss-include:half]]
" (buffer-string)))
    (should (= (org-truss-convert-public-in-buffer) 0))))

(ert-deftest org-truss-test-add-link-to-an-empty-section ()
  "A link added to a section with nothing but a drawer goes under the drawer."
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
    (org-truss-add-link (org-truss-test--heading-pos "Empty") "A")
    (should (equal (plist-get (org-truss--own (org-truss-test--heading-pos "Empty")) :items)
                   '("A")))
    (should (eq (org-truss-cluster-role
                 (car (org-truss-section-children (org-truss-model-structure (org-truss-read))))
                 'telling)
                'ask))))

(ert-deftest org-truss-test-add-section ()
  "A new section goes last under its parent, with its roles."
  (org-truss-test--with org-truss-test--file
    (org-truss-add-section (org-truss--part-pos "structure") "Ask" '((telling . ask)))
    (let* ((root (org-truss-model-structure (org-truss-read)))
           (last (car (last (org-truss-section-children root)))))
      (should (equal (org-truss-section-label last) "Ask"))
      (should (equal (org-truss-section-roles last) '((telling . ask)))))))

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
      (should (equal (org-truss-member-label (org-truss-heading-by-ref model "half")) "Agendas repeat"))
      (should (equal (org-truss-cluster-refs (org-truss-test--m model "Move to fortnightly"))
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
  "No line of a guide starts the way Org syntax does -- a block or a keyword,
a heading, a drawer line -- since a guide sits in a drawer in the file, and
Org reads such a line for what it looks like: with `org-hide-block-startup',
a line opening with #+begin_ stops org-mode starting at all."
  (dolist (entry org-truss--guides)
    (dolist (text (cdr entry))
      (dolist (line (split-string text "\n"))
        (should-not (string-match-p "\\`[ \t]*\\(?:#\\+\\|\\*+ \\|:[[:alnum:]_-]+:[ \t]*\\'\\)"
                                    line)))))
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
        (should (> n 3))))))

(ert-deftest org-truss-test-preamble-fits ()
  "No line of the head comment runs past 80 columns but the commands, which
are copied, not read."
  (dolist (org-truss-language '(en ja))
    (dolist (line (split-string (apply #'org-truss--pick org-truss--preamble-text) "\n"))
      (unless (string-match-p "emacs --batch" line)
        (should (<= (string-width line) 80))))))

(ert-deftest org-truss-test-skeleton ()
  "A new file has its parts and empty fields, headed in English whatever the
language; the guidance is in the language.  Its first line keeps what is
attached to its headings beside it, and its head comment names the
directories there."
  (dolist (org-truss-language '(en ja))
    (org-truss-test--with (org-truss-skeleton "T")
      (let ((model (org-truss-read)))
        (should (equal (org-truss-model-title model) "T"))
        (should-not (org-truss-cluster-patterns (org-truss-model-structure model)))
        (should (string-prefix-p (concat "# -*- org-attach-id-dir: \"attach/\"; -*-\n"
                                         "#+title: T\n\n" (org-truss--preamble) "\n* Brief\n")
                                 (buffer-string)))
        (should (equal (hack-local-variables-prop-line) '((org-attach-id-dir . "attach/"))))
        (dolist (dir '("^#   sources/ " "^#   notes/ " "^#   attach/ " "^#   out/ "))
          (should (string-match-p dir (buffer-string))))
        (should (equal (org-map-entries (lambda () (org-get-heading t t t t)))
                       '("Brief" "Reader" "Question" "Response wanted" "Constraints"
                         "Subject" "Premises" "Issue" "Constraints" "Members" "Structure")))
        (should (string-match-p (if (eq org-truss-language 'ja)
                                    "^# この truss\\.org から文書を一つ作ります。"
                                  "^# This truss\\.org makes one document:")
                                (buffer-string)))
        (should (string-match-p (if (eq org-truss-language 'ja)
                                    "^この文書が満たすべき条件。"
                                  "^What the document must satisfy\\.")
                                (buffer-string)))
        (should (string-match-p ":TRUSS_BREAKDOWN: reader-question-response-constraints\n"
                                (buffer-string)))
        (should (eq (org-truss-part-breakdown (org-truss-model-brief model))
                    'reader-question-response-constraints))
        (should (eq (org-truss-part-breakdown (org-truss-model-subject model))
                    'premises-issue-constraints))
        (should (equal (mapcar #'car (org-truss-test--fields (org-truss-model-brief model)))
                       '(((breakdown . reader)) ((breakdown . question))
                         ((breakdown . response)) ((breakdown . constraints)))))
        (should (equal (mapcar #'car (org-truss-test--fields (org-truss-model-subject model)))
                       '(((breakdown . premises)) ((breakdown . issue)) ((breakdown . constraints)))))
        (should (seq-every-p (lambda (f) (string-empty-p (cdr f)))
                             (append (org-truss-test--fields (org-truss-model-brief model))
                                     (org-truss-test--fields (org-truss-model-subject model)))))
        (should-not (plist-get (org-truss-checks model) :gaps))
        (should (org-truss-model-structure model))
        (should (null (org-truss-model-members model)))))))

(ert-deftest org-truss-test-add-place ()
  "A heading put in for a role goes where the pattern lists it among the
headings there, under any heading; a field is given its guide."
  (org-truss-test--with org-truss-test--conditions-file
    (set-marker (org-truss-add-place (org-truss--part-pos "brief") 'breakdown 'constraints) nil)
    (set-marker (org-truss-add-place (org-truss--part-pos "subject") 'breakdown 'premises) nil)
    (let ((model (org-truss-read)))
      (should (equal (mapcar #'org-truss-member-label (org-truss-part-children (org-truss-model-brief model)))
                     '("Reader" "Their question" "Response wanted" "Constraints")))
      (should (equal (mapcar #'org-truss-member-label (org-truss-part-children (org-truss-model-subject model)))
                     '("Premises" "Issue" "Constraints")))
      (should (string-match-p ":TRUSS_BREAKDOWN_ROLE: premises\n:END:\n:GUIDE:\nWhat is taken as given"
                              (buffer-string)))
      (should-not (plist-get (org-truss-checks model) :gaps)))))

(ert-deftest org-truss-test-refresh-guides ()
  "Refreshing puts the current guidance back, adds it where it was deleted,
and leaves everything else as it was, a guide of your own included.  A
file without the first line that keeps its attachments beside it is given
it, and the buffer takes it at once."
  (let ((org-truss-language 'ja))
    (org-truss-test--with "#+title: T

# An old preamble.

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
The board.
** Mine
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: mine
:END:
:GUIDE:
My own.
:END:

* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A member
:GUIDE:
Not a part's.
:END:
"
      (org-truss-refresh-guides-in-buffer)
      (let ((text (buffer-string)))
        (should (string-prefix-p (concat "# -*- org-attach-id-dir: \"attach/\"; -*-\n"
                                         "#+title: T\n\n" (org-truss--preamble) "\n* 与件\n")
                                 text))
        (should (equal org-attach-id-dir "attach/"))
        (should-not (string-match-p "Old wording\\|An old preamble" text))
        (should (string-match-p (concat ":TRUSS_PART: brief\n"
                                        ":TRUSS_BREAKDOWN: reader-question-response-constraints\n"
                                        ":END:\n:GUIDE:\nこの文書が満たすべき条件。\\(?:.*\n\\)*?:END:\n"
                                        "Notes on the brief\\.")
                                text))
        (should (string-match-p (concat ":TRUSS_BREAKDOWN_ROLE: reader\n:END:\n:GUIDE:\n"
                                        "誰が読むか。.*\n:END:\nThe board\\.")
                                text))
        (should (string-match-p ":TRUSS_BREAKDOWN_ROLE: mine\n:END:\n:GUIDE:\nMy own\\." text))
        (should (string-match-p ":TRUSS_PART: members\n:END:\n:GUIDE:\n考えたこと：" text))
        (should (string-match-p ":GUIDE:\nNot a part's\\.\n:END:" text))
        (org-truss-refresh-guides-in-buffer)
        (should (equal (buffer-string) text))))))

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

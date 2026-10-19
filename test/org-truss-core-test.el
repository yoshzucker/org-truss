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
:TRUSS_GROUNDS: calendar export
:END:
#+begin_public
Reviews ran past the hour eight times this quarter.
#+end_public

** Half the items repeat
:PROPERTIES:
:CUSTOM_ID: half
:TRUSS_LOGIC: reasons
:TRUSS_GROUNDS: [[#long]]
:END:
Robin keeps raising the same items; see [[#diff]].
#+begin_public Most items come back unchanged
Half of each agenda repeats the week before, as [[#long]] shows.
#+end_public
*** Agenda diff                                                  :noexport:
:PROPERTIES:
:CUSTOM_ID: diff
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: agendas, weeks 1-12
:END:
*** Items need a week to move                                    :assumption:
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
#+begin_public
We assume most items need more than a week to change.
#+end_public
*** Some items are urgent
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_BREAKDOWN: parts
:END:
#+begin_public
Some items cannot wait two weeks.
#+end_public
**** Urgent items go to chat
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: part
:TRUSS_GROUNDS: team agreement
:END:
**** Who decides what is urgent
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: part
:END:

** Move to fortnightly
:PROPERTIES:
:CUSTOM_ID: move
:TRUSS_GROUNDS: [[#half]]
:TRUSS_LOGIC: deduction
:END:
#+begin_public
Hold the review every other week.
#+end_public
*** A meeting that repeats itself can meet less
:PROPERTIES:
:TRUSS_LOGIC_ROLE: major
:END:

** Unused aside
:PROPERTIES:
:CUSTOM_ID: aside
:TRUSS_GROUNDS: hallway
:END:

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
- [[#long]]

** Rain
:PROPERTIES:
:TRUSS_TELLING_ROLE: rain
:END:
#+begin_public Why it drags
#+end_public
- [[#half]]

** Umbrella
:PROPERTIES:
:TRUSS_TELLING_ROLE: umbrella
:END:
- [[#move]]
- [[#none]]
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
:TRUSS_GROUNDS: finance, 3 October
:END:
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
** Premises
:PROPERTIES:
:TRUSS_TELLING_ROLE: premises
:END:
- [[#budget]]
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
**** The rule asks for a check before driving
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: rule 6
:END:
**** The rule asks for a check after driving
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: rule 6
:END:
**** The check may be made by video
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: notice 2(2)
:END:
*** A manager is named for five cars or more
:PROPERTIES:
:CUSTOM_ID: five
:TRUSS_GROUNDS: law 74-3
:END:
*** The law binds us, so we must check
:PROPERTIES:
:TRUSS_GROUNDS: [[#five]]
:END:

* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** The rule may apply to us
:PROPERTIES:
:CUSTOM_ID: may
:TRUSS_GROUNDS: [[#five]]
:END:
** Drivers are checked before and after driving
:PROPERTIES:
:CUSTOM_ID: checked
:TRUSS_GROUNDS: [[#may]] [[#rule]]
:TRUSS_BREAKDOWN: steps
:END:
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
:TRUSS_GROUNDS: tester manual
:END:

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Background
:PROPERTIES:
:TRUSS_TELLING_ROLE: situation
:END:
- [[#rule][The rules ask for a check before and after driving.]]
** What we do
:PROPERTIES:
:TRUSS_TELLING_ROLE: conclusion
:END:
- [[#checked]]
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
:TRUSS_GROUNDS: ordinance, article 9-10
:END:
** Check before every test
:PROPERTIES:
:CUSTOM_ID: check
:TRUSS_BREAKDOWN: steps
:TRUSS_GROUNDS: [[#law]]
:END:
*** Meet the driver face to face
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
**** A video call counts as face to face
:PROPERTIES:
:TRUSS_GROUNDS: notice, 2022
:END:
*** Note the reading                                              :noexport:
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
*** Breathe into the checker
:PROPERTIES:
:TRUSS_BREAKDOWN_ROLE: step
:END:
#+begin_public
The driver breathes into the checker.
#+end_public
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
- [[#check]]
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
:TRUSS_GROUNDS: incident log
:END:
*** Alcohol slows reactions
:PROPERTIES:
:TRUSS_TELLING_ROLE: reason
:TRUSS_GROUNDS: textbook
:END:

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Do
- [[#check]]
- [[#needs]]
- [[#safer]]
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
- [[#m1]]
** 空
:PROPERTIES:
:TRUSS_TELLING_ROLE: sky
:END:
#+begin_public Where we stand
#+end_public
** Umbrella
:PROPERTIES:
:TRUSS_TELLING_ROLE: umbrella
:END:
#+begin_public
Meet every other week.
#+end_public
** Notes for later
"
  "A file part written: a heading playing no role, sections out of order.")

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
:TRUSS_GROUNDS: x
:END:
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
:TRUSS_GROUNDS: the minutes of May
:END:
*** By a link
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: [[moor:6f1c::3][Minutes l. 3]]
:END:
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
:TRUSS_GROUNDS: [[#fact]]
:END:
*** Through an argument
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: [[#argued]]
:END:
*** Through a bare one
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: [[#bare]] [[#fact]]
:END:
*** On a cycle
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:TRUSS_GROUNDS: [[#a]]
:END:
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
:TRUSS_GROUNDS: [[#gone]]
:END:
*** No role
** Points at a bare one
:PROPERTIES:
:TRUSS_GROUNDS: [[#bare]] [[#argued]]
:END:
** Fact
:PROPERTIES:
:CUSTOM_ID: fact
:TRUSS_GROUNDS: minutes
:END:
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
:TRUSS_GROUNDS: [[#b]]
:END:
** B
:PROPERTIES:
:CUSTOM_ID: b
:TRUSS_GROUNDS: [[#a]]
:END:
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
  "A member has grounds in TRUSS_GROUNDS, links to members or sources or
words; in a quotation in its text; or in a link in its text, to a member
or a source."
  (org-truss-test--with org-truss-test--grounds-file
    (let* ((model (org-truss-read))
           (m (lambda (label) (org-truss-test--m model label))))
      (should (equal (org-truss-member-sources (funcall m "By words")) "the minutes of May"))
      (should (equal (org-truss-member-sources (funcall m "By a link"))
                     "[[moor:6f1c::3][Minutes l. 3]]"))
      (should-not (org-truss-member-cited (funcall m "By a link")))
      (should (equal (org-truss-member-quoted (funcall m "By a quote")) "We agreed."))
      (should (equal (org-truss-member-cited (funcall m "In its text"))
                     "[[file:sources/a.pdf][the rule]]"))
      (dolist (label '("By words" "By a link" "By a quote" "In its text" "Through a member"))
        (should (org-truss-has-grounds-p (funcall m label))))
      (should-not (org-truss-has-grounds-p (funcall m "Nothing")))
      (should (equal (org-truss-member-grounds (funcall m "Through a bare one")) '("bare" "fact")))
      (should-not (org-truss-member-sources (funcall m "Through a bare one"))))))

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
  "A heading that must have grounds lacks them when its TRUSS_GROUNDS names
nothing -- a link to a member or a source, or words -- and its text neither
quotes a source nor links to one.  What a link points to is not read."
  (org-truss-test--with org-truss-test--grounds-file
    (let* ((model (org-truss-read))
           (missing (lambda (label) (org-truss-missing-grounds model (org-truss-test--m model label)))))
      (dolist (label '("By words" "By a link" "By a quote" "In its text" "Through a member"
                       "Through an argument" "Through a bare one" "On a cycle" "Only broken"
                       "Assumed" "Argued below" "No role"))
        (should-not (funcall missing label)))
      (should (funcall missing "Unsupported"))
      (should (funcall missing "Nothing"))
      (should (equal (org-truss-test--labels (plist-get (org-truss-checks model) :no-grounds))
                     '("Unsupported" "Nothing"))))))

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
  "What any heading points to as grounds must hold: a link in TRUSS_GROUNDS
to a member that does not is weak, wherever it is written, whether the
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
  "A link in a heading's text to a member is grounds, as one in its
TRUSS_GROUNDS is: it gives the heading grounds, and what it points to must
hold and be there.  A section reads its text alike, but an item listing a
member is what it tells, not grounds; and a section with a logic asks
grounds of its reasons as a member does."
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
:TRUSS_GROUNDS: [[#bare]]
:END:
As [[#bare]] says, twice.
*** Cites nothing there
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
As [[#gone]] says.
** Fact
:PROPERTIES:
:CUSTOM_ID: fact
:TRUSS_GROUNDS: minutes
:END:
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
- [[#fact]]
** Because
:PROPERTIES:
:TRUSS_LOGIC_ROLE: reason
:END:
As [[#fact]] shows.
- [[#bare]]
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
      (should (equal (funcall pairs :weak-grounds) '(("Cites a bare one" . "bare"))))
      (should (equal (funcall pairs :broken-grounds) '(("Cites nothing there" . "gone"))))
      (should-not (org-truss-cluster-text-grounds (funcall section "Why")))
      (should (equal (org-truss-cluster-text-grounds (funcall section "Because")) '("fact")))
      (should (equal (mapcar #'org-truss-cluster-label (plist-get checks :no-grounds)) '("Why"))))))

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
:TRUSS_GROUNDS: [[file:sources/law.pdf::3][the law]] [[moor:kept::2][kept]]
:END:
See [[./sources/law.pdf]] and [[https://example.com/gone]].
** Cites what is not
:PROPERTIES:
:TRUSS_GROUNDS: [[moor:lost][lost]]
:END:
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
  "TRUSS_GROUNDS lists links to members, then sources.  Setting either keeps
the other, and with neither it goes."
  (should (equal (org-truss--grounds-sources "[[#a]]  the  minutes [[#b]]") "the minutes"))
  (should-not (org-truss--grounds-sources "[[#a]] [[#b]]"))
  (should (equal (org-truss--grounds-value '("a" "*B") "minutes") "[[#a]] [[*B]] minutes"))
  (should (equal (org-truss--grounds-value nil "minutes") "minutes"))
  (org-truss-test--with org-truss-test--file
    (let ((half (org-truss-test--heading-pos "Half the items repeat")))
      (org-truss-set-sources half "the agendas")
      (should (equal (org-entry-get half "TRUSS_GROUNDS") "[[#long]] the agendas"))
      (org-truss-set-grounds half '("long" "aside"))
      (should (equal (org-entry-get half "TRUSS_GROUNDS") "[[#long]] [[#aside]] the agendas"))
      (org-truss-set-grounds half nil)
      (should (equal (org-entry-get half "TRUSS_GROUNDS") "the agendas"))
      (org-truss-set-sources half " ")
      (should-not (org-entry-get half "TRUSS_GROUNDS")))
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
                     '(("Move to fortnightly" (logic minor . 1)))))
      (should-not (plist-get checks :no-role))
      (should-not (plist-get checks :out-of-order))
      (should (equal (org-truss-test--labels (plist-get checks :no-grounds))
                     '("Some items are urgent" "A meeting that repeats itself can meet less")))
      (should (equal (mapcar #'cdr (plist-get checks :broken-links)) '("none")))
      (should-not (plist-get checks :broken-grounds))
      (should-not (plist-get checks :duplicates))))
  (org-truss-test--with (replace-regexp-in-string
                         ":TRUSS_GROUNDS: \\[\\[#half\\]\\]" ":TRUSS_GROUNDS: [[#half]] [[#gone]]"
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
      (should (string-match-p "^truss\\.org:[0-9]+: \\[\\[#none\\]\\] in Umbrella$" report))
      (should (string-match-p "^truss\\.org:[0-9]+: Some items are urgent -- no grounds$" report))
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
  "Two members with one id are reported, since a link cannot tell them apart;
two with one label are not, since nothing points by label."
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
"
    (let ((model (org-truss-read)))
      (should (equal (org-truss-model-duplicates model) '("x")))
      (should (equal (org-truss-member-label (org-truss-member-by-ref model "x")) "One"))
      (should (string-match-p "^f:[0-9]+: Two -- #x, which another member has too$"
                              (org-truss-check-report model "f"))))))

;;;; Reading

(ert-deftest org-truss-test-own-text ()
  "Links in the public block and in drawers are not references; inline ones are."
  (org-truss-test--with org-truss-test--file
    (let ((own (org-truss--own (org-truss-test--heading-pos "Half the items repeat"))))
      (should (equal (plist-get own :links) '("diff")))
      (should (equal (car (plist-get own :public)) "Most items come back unchanged"))
      (should (string-match-p "\\`Half of each agenda" (cdr (plist-get own :public))))
      (should (equal (plist-get own :props) '(("CUSTOM_ID" . "half")
                                              ("TRUSS_LOGIC" . "reasons")
                                              ("TRUSS_GROUNDS" . "[[#long]]")))))))

(ert-deftest org-truss-test-references ()
  "A link or a ground points to a member by its CUSTOM_ID.  One that names a
heading points to no member, and shows as broken; anything else in
TRUSS_GROUNDS is a source."
  (should (equal (org-truss--refs-in "[[#a]] and [[#b][words]], [[*C]] [[https://x]]")
                 '("a" "b" "*C")))
  (should (equal (org-truss--grounds-refs "[[#a]] [[#b]]") '("a" "b")))
  (should-not (org-truss--grounds-refs "Old one; Old two"))
  (should (equal (org-truss--link-item "a" "w") "- [[#a][w]]\n"))
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-member-label (org-truss-member-by-ref model "half"))
                     "Half the items repeat"))
      (should (equal (org-truss-member-id (org-truss-test--m model "Lone remark")) nil))
      (should-not (org-truss-member-by-ref model "Half the items repeat")))))

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
                                    ":TRUSS_BREAKDOWN_ROLE: part\n:TRUSS_GROUNDS: team agreement\n:END:\n")
                            (buffer-string)))))

(defun org-truss-test--fields (part)
  "Return the members right under PART, its fields, as (ROLES . TEXT)."
  (mapcar (lambda (field) (cons (org-truss-member-roles field) (org-truss-member-notes field)))
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
other, as are the members under it; its text is its notes.  The parts are
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
* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** A claim
:PROPERTIES:
:ID:       abcdef
:END:
#+begin_public Said
[[attachment:shot.png]]
#+end_public
See [[attachment:shot.png][the shot]].
** Another
[[attachment:shot.png]]
"))
      (with-current-buffer (find-file-noselect file)
        (unwind-protect
            (let* ((model (org-truss-read))
                   (claim (org-truss-member-by-label model "A claim")))
              (should (equal (cdr (org-truss-member-public claim))
                             "[[file:attach/ab/cdef/shot.png]]"))
              (should (equal (org-truss-member-notes claim)
                             "See [[file:attach/ab/cdef/shot.png][the shot]]."))
              (should (equal (org-truss-member-notes (org-truss-member-by-label model "Another"))
                             "[[attachment:shot.png]]"))
              (should (string-match-p "\\[\\[attachment:shot\\.png\\]\\]\n#\\+end_public"
                                      (buffer-string))))
          (kill-buffer))))))

;;;; Editing the structure

(ert-deftest org-truss-test-convert-references ()
  "Links and grounds that name headings come to point by id, the member
named being given one, and the sources named beside stay; a heading no
member has stays, broken."
  (org-truss-test--with (replace-regexp-in-string
                         "^- \\[\\[#\\(long\\|half\\)\\]"
                         (lambda (m) (if (equal (match-string 1 m) "long")
                                         "- [[*Reviews run long]" "- [[*Half the items repeat]"))
                         (replace-regexp-in-string
                          ":TRUSS_GROUNDS: \\[\\[#half\\]\\]"
                          ":TRUSS_GROUNDS: [[*Half the items repeat]] [[*Lone remark]] [[*Nobody]] the agendas"
                          (replace-regexp-in-string ":CUSTOM_ID: half\n" "" org-truss-test--file)))
    (should (= (org-truss-convert-references-in-buffer) 4))
    (let* ((model (org-truss-read))
           (lone (org-truss-member-id (org-truss-test--m model "Lone remark")))
           (half (org-truss-member-id (org-truss-test--m model "Half the items repeat")))
           (move (org-truss-test--m model "Move to fortnightly")))
      (should (equal (list half lone) '("m1" "m2")))
      (should (equal (org-truss-member-grounds move) '("m1" "m2" "*Nobody")))
      (should (equal (org-truss-member-sources move) "the agendas"))
      (should (equal (org-truss-member-grounds (org-truss-test--m model "Half the items repeat"))
                     '("long")))
      (should (equal (org-truss-section-links (car (org-truss-section-children
                                                    (org-truss-model-structure model))))
                     '("long")))
      (should (string-match-p "^- \\[\\[#m1\\]\\]$" (buffer-string)))
      (should (string-match-p "as \\[\\[#long\\]\\] shows" (buffer-string))))
    (should (= (org-truss-convert-references-in-buffer) 0))))

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
      (should (equal (org-truss-section-links (funcall by-label "Sky"))
                     '("long")))
      (should (equal (org-truss-section-links (funcall by-label "Umbrella"))
                     '("move" "none")))
      (should (eq (org-truss-cluster-role (funcall by-label "Umbrella") 'telling) 'answer))
      (should (eq (org-truss-cluster-role (funcall by-label "Question") 'telling) 'question))
      (should (string-match-p "^\\*\\* Question\n:PROPERTIES:\n:TRUSS_TELLING_ROLE: question\n:END:"
                              (buffer-string)))
      (should (equal (car (org-truss-section-public (funcall by-label "Rain"))) "Why it drags"))
      (should (equal (org-truss-section-links (funcall by-label "Rain"))
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
- [[#inner]]
"
    (org-truss-apply-section-telling (org-truss--part-pos "structure") 'scqa)
    (let* ((root (org-truss-model-structure (org-truss-read)))
           (answer (nth 3 (org-truss-section-children root))))
      (should (equal (org-truss-section-label answer) "Umbrella"))
      (should (eq (org-truss-section-telling answer) 'sky-rain-umbrella))
      (should (equal (org-truss-section-links (car (org-truss-section-children answer)))
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
  (org-truss-test--with org-truss-test--file
    (let ((root (org-truss--part-pos "structure")))
      (should (equal (org-truss-unwrap root) '("Rain")))
      (should (= 3 (length (org-truss-section-children
                            (org-truss-model-structure (org-truss-read))))))
      (org-truss-set-pattern root 'breakdown '5w1h)
      (should (null (org-truss-unwrap root t)))
      (let ((section (org-truss-model-structure (org-truss-read))))
        (should (null (org-truss-section-children section)))
        (should (null (org-truss-cluster-patterns section)))
        (should (equal (org-truss-section-links section)
                       '("long" "half" "move" "none")))))))

(ert-deftest org-truss-test-dissolve ()
  "A dissolved section hands its links to the section above."
  (org-truss-test--with org-truss-test--file
    (should (null (org-truss-dissolve (org-truss-test--heading-pos "Sky")
                                      (org-truss--part-pos "structure"))))
    (let ((root (org-truss-model-structure (org-truss-read))))
      (should (equal (org-truss-test--section-labels root) '("Rain" "Umbrella")))
      (should (equal (org-truss-section-links root) '("long"))))))

(ert-deftest org-truss-test-links ()
  "Links are added after the last one, moved, reordered and removed."
  (org-truss-test--with org-truss-test--file
    (let ((links-of (lambda (label)
                      (plist-get (org-truss--own (org-truss-test--heading-pos label)) :items))))
      (org-truss-add-link (org-truss-test--heading-pos "Sky") "aside")
      (should (equal (funcall links-of "Sky") '("long" "aside")))
      (should (string-match-p "^- \\[\\[#long\\]\\]\n- \\[\\[#aside\\]\\]$" (buffer-string)))
      (org-truss-shift-link (org-truss-test--heading-pos "Sky") "aside" -1)
      (should (equal (funcall links-of "Sky") '("aside" "long")))
      (org-truss-move-link (org-truss-test--heading-pos "Sky") "aside"
                           (org-truss-test--heading-pos "Rain"))
      (should (equal (funcall links-of "Sky") '("long")))
      (should (equal (funcall links-of "Rain") '("half" "aside")))
      (org-truss-remove-link (org-truss-test--heading-pos "Rain") "aside")
      (should (equal (funcall links-of "Rain") '("half"))))))

(defun org-truss-test--wording (section label)
  "Return the words the section labelled SECTION tells LABEL in, read anew."
  (let ((model (org-truss-read)))
    (org-truss-section-wording
     (seq-find (lambda (s) (equal (org-truss-section-label s) section))
               (cons (org-truss-model-structure model) (org-truss-sections model)))
     label)))

(ert-deftest org-truss-test-link-wording ()
  "A link's description is what its section tells the member in.  It is
written and taken off in place, and goes with the link when the member is
renamed, the link moved, or the section unwrapped."
  (org-truss-test--with org-truss-test--file
    (should (org-truss-set-wording (org-truss-test--heading-pos "Sky")
                                   "long" " Our reviews overran "))
    (should (equal (org-truss-test--wording "Sky" "long") "Our reviews overran"))
    (should (string-match-p "^- \\[\\[#long\\]\\[Our reviews overran\\]\\]$"
                            (buffer-string)))
    (should (equal (org-truss-section-links
                    (car (org-truss-section-children (org-truss-model-structure (org-truss-read)))))
                   '("long")))
    (org-truss-rename (org-truss-test--heading-pos "Reviews run long") "Reviews overrun")
    (should (equal (org-truss-test--wording "Sky" "long") "Our reviews overran"))
    (org-truss-move-link (org-truss-test--heading-pos "Sky") "long"
                         (org-truss-test--heading-pos "Rain"))
    (should (equal (org-truss-test--wording "Rain" "long") "Our reviews overran"))
    (should-not (org-truss-set-wording (org-truss-test--heading-pos "Sky") "long" "x"))
    (should-error (org-truss-set-wording (org-truss-test--heading-pos "Rain")
                                         "long" "a [b]")
                  :type 'user-error)
    (org-truss-unwrap (org-truss--part-pos "structure") t)
    (should (equal (org-truss-test--wording "Structure" "long") "Our reviews overran"))
    (org-truss-set-wording (org-truss--part-pos "structure") "long" "  ")
    (should-not (org-truss-test--wording "Structure" "long"))
    (should (string-match-p "^- \\[\\[#long\\]\\]$" (buffer-string)))))

(ert-deftest org-truss-test-public-body ()
  "Where a public block's text starts is found, or a block is written for it:
before the items that list members, or at the end of the heading's own
text.  An empty block gets a line to write on, and one left empty can be
taken away."
  (org-truss-test--with org-truss-test--file
    (let ((section (lambda (label)
                     (seq-find (lambda (s) (equal (org-truss-section-label s) label))
                               (org-truss-sections (org-truss-read))))))
      (goto-char (org-truss-public-body (org-truss-test--heading-pos "Sky")))
      (insert "Where we are.")
      (should (equal (org-truss-section-public (funcall section "Sky"))
                     '(nil . "Where we are.")))
      (should (string-match-p
               ":TRUSS_TELLING_ROLE: sky\n:END:\n#\\+begin_public\nWhere we are\\.\n#\\+end_public\n- \\[\\[#long"
               (buffer-string)))
      (goto-char (org-truss-public-body (org-truss-test--heading-pos "Rain")))
      (insert "Why.")
      (should (equal (org-truss-section-public (funcall section "Rain"))
                     '("Why it drags" . "Why.")))
      (goto-char (org-truss-public-body (org-truss-test--heading-pos "Lone remark")))
      (should (looking-at "\n#\\+end_public\n\n\\* Structure"))
      (org-truss-drop-empty-public (point-min) (point-max))
      (should (string-match-p "^\\*\\* Lone remark\n+\\* Structure" (buffer-string)))
      (should (string-match-p "Where we are\\." (buffer-string))))))

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
      (should (equal (org-truss-member-label (org-truss-member-by-ref model "half")) "Agendas repeat"))
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
                                  "#+begin_public\nThe lead.\n#+end_public\n")
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

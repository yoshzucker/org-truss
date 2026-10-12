;;; org-truss-core-test.el --- Tests for org-truss-core  -*- lexical-binding: t; -*-

;;; Commentary:

;; emacs --batch -Q -L . -l test/org-truss-core-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org-truss-core)

(defconst org-truss-test--file "#+title: Fortnightly reviews

* Brief
:PROPERTIES:
:TRUSS_PART: brief
:END:
** Reader
:PROPERTIES:
:TRUSS_FIELD: reader
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
:TRUSS_SOURCE: calendar export
:END:
#+begin_public
Reviews ran past the hour eight times this quarter.
#+end_public

** Half the items repeat
:PROPERTIES:
:CUSTOM_ID: half
:TRUSS_GROUNDS: [[#long]]
:END:
Robin keeps raising the same items; see [[#diff]].
#+begin_public Most items come back unchanged
Half of each agenda repeats the week before, as [[#long]] shows.
#+end_public
*** Agenda diff                                                  :noexport:
:PROPERTIES:
:CUSTOM_ID: diff
:TRUSS_SOURCE: agendas, weeks 1-12
:END:
*** Items need a week to move                                    :assumption:
#+begin_public
We assume most items need more than a week to change.
#+end_public
*** Some items are urgent                                           :against:
#+begin_public
Some items cannot wait two weeks.
#+end_public
**** Urgent items go to chat                                       :against:
:PROPERTIES:
:TRUSS_SOURCE: team agreement
:END:
**** Who decides what is urgent                           :question:against:

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
:TRUSS_ROLE: major
:END:

** Unused aside
:PROPERTIES:
:CUSTOM_ID: aside
:TRUSS_SOURCE: hallway
:END:

** Lone remark

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_LOGIC: proposal
:TRUSS_TELLING: sky-rain-umbrella
:END:
** Sky
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
- [[#long]]

** Rain
:PROPERTIES:
:TRUSS_ROLE: interpretation
:END:
#+begin_public Why it drags
#+end_public
- [[#half]]

** Umbrella
:PROPERTIES:
:TRUSS_ROLE: conclusion
:END:
- [[#move]]
- [[#none]]
"
  "A truss file covering every kind of member and a structure with a broken link.")

(defconst org-truss-test--conditions-file "#+title: Checks before a test

* Brief
:PROPERTIES:
:TRUSS_PART: brief
:END:
** Reader
:PROPERTIES:
:TRUSS_FIELD: reader
:END:
The safety board.
** Their question
:PROPERTIES:
:TRUSS_FIELD: question
:END:
** Response wanted
:PROPERTIES:
:TRUSS_FIELD: response
:END:

* Subject
:PROPERTIES:
:TRUSS_PART: subject
:END:
** Issue
:PROPERTIES:
:TRUSS_FIELD: issue
:END:
*** Nobody checks before a test
** Constraints
:PROPERTIES:
:TRUSS_FIELD: constraints
:END:
Finance said so at the October meeting.
*** No budget this year
:PROPERTIES:
:CUSTOM_ID: budget
:TRUSS_SOURCE: finance, 3 October
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
:TRUSS_LOGIC: proposal
:END:
** Premises
:PROPERTIES:
:TRUSS_ROLE: premises
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
:TRUSS_FIELD: premises
:END:
*** How many cars we run                                           :question:
** Constraints
:PROPERTIES:
:TRUSS_FIELD: constraints
:END:
*** The manager checks every driver before and after driving
:PROPERTIES:
:CUSTOM_ID: rule
:TRUSS_LOGIC: parts
:END:
**** The rule asks for a check before driving
:PROPERTIES:
:TRUSS_SOURCE: rule 6
:END:
**** The rule asks for a check after driving
:PROPERTIES:
:TRUSS_SOURCE: rule 6
:END:
**** The check may be made by video
:PROPERTIES:
:TRUSS_SOURCE: notice 2(2)
:END:
*** A manager is named for five cars or more
:PROPERTIES:
:CUSTOM_ID: five
:TRUSS_SOURCE: law 74-3
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
:TRUSS_LOGIC: steps
:END:
*** The driver blows into the tester
*** The manager reads it
** The tester reads zero when sober
:PROPERTIES:
:TRUSS_SOURCE: tester manual
:END:

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Background
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
- [[#rule][The rules ask for a check before and after driving.]]
** What we do
:PROPERTIES:
:TRUSS_ROLE: conclusion
:END:
- [[#checked]]
"
  "A truss file whose subject holds a cluster of facts under the one that
sums them up, with a member in the wrong part on each side.")

(defconst org-truss-test--steps-file "#+title: Checks before a test

* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** The law asks for a check
:PROPERTIES:
:CUSTOM_ID: law
:TRUSS_SOURCE: ordinance, article 9-10
:END:
** Check before every test
:PROPERTIES:
:CUSTOM_ID: check
:TRUSS_LOGIC: steps
:TRUSS_GROUNDS: [[#law]]
:END:
*** Meet the driver face to face
**** A video call counts as face to face
:PROPERTIES:
:TRUSS_SOURCE: notice, 2022
:END:
*** Note the reading                                              :noexport:
*** Breathe into the checker
#+begin_public
The driver breathes into the checker.
#+end_public
*** The checker may be broken                                      :against:
** Steps with nothing behind them
:PROPERTIES:
:TRUSS_LOGIC: steps
:END:
*** The only step

* Structure
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Do
:PROPERTIES:
:TRUSS_ROLE: conclusion
:END:
- [[#check]]
"
  "A truss file with a member that says how, in steps.")

(defconst org-truss-test--how-file "#+title: Checks before a test

* Members
:PROPERTIES:
:TRUSS_PART: members
:END:
** Check before every test
:PROPERTIES:
:CUSTOM_ID: check
:TRUSS_LOGIC: 5w1h
:END:
*** The driver's manager
:PROPERTIES:
:TRUSS_ROLE: who
:END:
*** In the office or by video call
:PROPERTIES:
:TRUSS_ROLE: where
:END:
*** Before the first run of the day
:PROPERTIES:
:TRUSS_ROLE: when
:END:
*** As follows
:PROPERTIES:
:TRUSS_ROLE: how
:TRUSS_LOGIC: steps
:END:
**** Meet the driver
**** Read the checker
** What a check needs
:PROPERTIES:
:CUSTOM_ID: needs
:TRUSS_LOGIC: parts
:END:
*** A checker that works
*** Someone to check
** Tests are safer checked
:PROPERTIES:
:CUSTOM_ID: safer
:TRUSS_TELLING: prep
:END:
*** A drunk driver crashed last year
:PROPERTIES:
:TRUSS_ROLE: example
:TRUSS_SOURCE: incident log
:END:
*** Alcohol slows reactions
:PROPERTIES:
:TRUSS_ROLE: reason
:TRUSS_SOURCE: textbook
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
  "A truss file with parts, labelled parts holding steps, and a PREP.")

(defmacro org-truss-test--with (text &rest body)
  "Run BODY in an Org buffer holding TEXT."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (org-mode)
     (goto-char (point-min))
     ,@body))

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

(ert-deftest org-truss-test-steps ()
  "Under a member that follows Steps, what is nested is its steps: they say
how, so they are not asked for support and do not support it.  What argues
against it is still an objection, and what is under a step supports the step."
  (org-truss-test--with org-truss-test--steps-file
    (let* ((model (org-truss-read))
           (kind (lambda (label) (org-truss-kind model (org-truss-test--m model label)))))
      (should (eq (funcall kind "Meet the driver face to face") 'step))
      (should (eq (funcall kind "Note the reading") 'step))
      (should (eq (funcall kind "The only step") 'step))
      (should (eq (funcall kind "A video call counts as face to face") 'fact))
      (should (eq (funcall kind "The checker may be broken") 'objection))
      (should (eq (funcall kind "Check before every test") 'claim))
      (should (eq (funcall kind "Steps with nothing behind them") 'bare))
      (should (equal (org-truss-test--labels
                      (org-truss-supports model (org-truss-test--m model "Check before every test")))
                     '("The law asks for a check")))
      (should (equal (org-truss-test--labels
                      (org-truss-how-children (org-truss-test--m model "Check before every test")))
                     '("Meet the driver face to face" "Note the reading"
                       "Breathe into the checker")))
      (should-not (plist-get (org-truss-checks model) :bare)))))

(ert-deftest org-truss-test-how-and-telling ()
  "Parts and labelled parts say how, as steps do.  Labelled parts are told in
the order of their roles, and the roles not filled are gaps.  A telling
pattern sits beside a logic pattern and adds its own roles."
  (org-truss-test--with org-truss-test--how-file
    (let* ((model (org-truss-read))
           (kind (lambda (label) (org-truss-kind model (org-truss-test--m model label))))
           (check (org-truss-test--m model "Check before every test")))
      (should (eq (funcall kind "The driver's manager") 'part))
      (should (eq (funcall kind "A checker that works") 'part))
      (should (eq (funcall kind "Meet the driver") 'step))
      (should (eq (funcall kind "As follows") 'part))
      (should (equal (org-truss-test--labels (org-truss-how-children check))
                     '("The driver's manager" "Before the first run of the day"
                       "In the office or by video call" "As follows")))
      (should (equal (org-truss-gaps check) '((what . 1) (why . 1))))
      (should (eq (org-truss-conclusion-position
                   (org-truss-test--m model "Tests are safer checked"))
                  'prep))))
  (org-truss-test--with (replace-regexp-in-string
                         ":TRUSS_TELLING: prep" ":TRUSS_LOGIC: deduction\n:TRUSS_TELLING: prep"
                         org-truss-test--how-file)
    (let ((member (org-truss-test--m (org-truss-read) "Tests are safer checked")))
      (should (equal (org-truss-member-roles member) '(major minor reason example)))
      (should (eq (org-truss-conclusion-position member) 'prep)))))

(defun org-truss-test--section-labels (section)
  (mapcar #'org-truss-section-label (org-truss-section-children section)))

;;;; Reading

(ert-deftest org-truss-test-own-text ()
  "Links in the public block and in drawers are not references; inline ones are."
  (org-truss-test--with org-truss-test--file
    (let ((own (org-truss--own (org-truss-test--heading-pos "Half the items repeat"))))
      (should (equal (plist-get own :links) '("diff")))
      (should (equal (car (plist-get own :public)) "Most items come back unchanged"))
      (should (string-match-p "\\`Half of each agenda" (cdr (plist-get own :public))))
      (should (equal (plist-get own :props) '(("CUSTOM_ID" . "half")
                                              ("TRUSS_GROUNDS" . "[[#long]]")))))))

(ert-deftest org-truss-test-references ()
  "A link or a ground points to a member by its CUSTOM_ID.  One that names a
heading points to no member, nor do grounds written as `;'-separated
headings, as files once wrote them: each shows as broken."
  (should (equal (org-truss--refs-in "[[#a]] and [[#b][words]], [[*C]] [[https://x]]")
                 '("a" "b" "*C")))
  (should (equal (org-truss--grounds-refs "[[#a]] [[#b]]") '("a" "b")))
  (should (equal (org-truss--grounds-refs "Old one; Old two") '("*Old one" "*Old two")))
  (should (equal (org-truss--grounds-value '("a" "*B")) "[[#a]] [[*B]]"))
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
    (should (string-match-p (concat "Urgent items go to chat +:against:\n:PROPERTIES:\n"
                                    ":CUSTOM_ID: m6\n:TRUSS_SOURCE: team agreement\n:END:\n")
                            (buffer-string)))))

(ert-deftest org-truss-test-brief ()
  "A brief field is its text, without the guidance drawer."
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-model-title model) "Fortnightly reviews"))
      (should (equal (org-truss-model-brief model) '((reader . "The team leads.")))))))

(ert-deftest org-truss-test-conditions ()
  "A heading under a field of the brief or the subject is a member: linked and
judged like one, but never asked to be placed.  The field's text is apart."
  (org-truss-test--with org-truss-test--conditions-file
    (let* ((model (org-truss-read))
           (budget (org-truss-test--m model "No budget this year")))
      (should (equal (org-truss-model-subject model)
                     '((issue . "") (constraints . "Finance said so at the October meeting."))))
      (should (equal (org-truss-test--labels
                      (alist-get '(subject constraints) (org-truss-model-conditions model)
                                 nil nil #'equal))
                     '("No budget this year" "The schedule is fixed")))
      (should (eq (org-truss-kind model budget) 'fact))
      (should (equal (org-truss-test--labels (car (org-truss-usage model)))
                     '("No budget this year")))
      (should (equal (org-truss-test--labels (plist-get (org-truss-checks model) :unplaced))
                     '("Check with a breathalyser")))
      (should (equal (org-truss-test--labels (org-truss-model-all model))
                     '("Nobody checks before a test" "No budget this year"
                       "The schedule is fixed" "Check with a breathalyser"))))))

(ert-deftest org-truss-test-kinds ()
  "Each kind follows from what is written on the member."
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (dolist (case '(("Reviews run long" . fact)
                      ("Half the items repeat" . claim)
                      ("Agenda diff" . fact)
                      ("Items need a week to move" . assumption)
                      ("Some items are urgent" . objection)
                      ("Urgent items go to chat" . fact)
                      ("Who decides what is urgent" . question)
                      ("Move to fortnightly" . claim)
                      ("A meeting that repeats itself can meet less" . bare)
                      ("Lone remark" . bare)))
        (should (eq (org-truss-kind model (org-truss-test--m model (car case)))
                    (cdr case)))))))

(ert-deftest org-truss-test-objections-do-not-support ()
  "What argues against a claim is not counted among its support."
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-test--labels
                      (org-truss-supports model (org-truss-test--m model "Half the items repeat")))
                     '("Agenda diff" "Items need a week to move" "Reviews run long"))))))

(ert-deftest org-truss-test-hypothesis-travels-through-grounds ()
  "A claim resting on an assumption is a hypothesis, and so is what rests on it."
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (org-truss-hypothesis-p model (org-truss-test--m model "Half the items repeat")))
      (should (org-truss-hypothesis-p model (org-truss-test--m model "Move to fortnightly")))
      (should-not (org-truss-hypothesis-p model (org-truss-test--m model "Reviews run long"))))))

(ert-deftest org-truss-test-hypothesis-survives-a-cycle ()
  "Grounds that name each other end instead of recursing forever."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
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
"
    (let ((model (org-truss-read)))
      (should-not (org-truss-hypothesis-p model (org-truss-test--m model "A"))))))

(ert-deftest org-truss-test-a-reply-is-not-an-unanswered-objection ()
  "Only an objection to a claim waits for an answer, and a question does not answer it."
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should-not (org-truss-unanswered-p model (org-truss-test--m model "Some items are urgent")))
      (should-not (org-truss-unanswered-p model (org-truss-test--m model "Urgent items go to chat")))
      (should-not (org-truss-unanswered-p model (org-truss-test--m model "Who decides what is urgent")))))
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Claim
*** Doubt                                                           :against:
**** Not known                                             :question:against:
"
    (let ((model (org-truss-read)))
      (should (org-truss-unanswered-p model (org-truss-test--m model "Doubt"))))))

(ert-deftest org-truss-test-argument-gaps ()
  "A deduction without its minor premise says so; induction wants two cases."
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (org-truss-gaps (org-truss-test--m model "Move to fortnightly"))
                     '((minor . 1))))
      (should (eq (org-truss-conclusion-position (org-truss-test--m model "Move to fortnightly"))
                  'last))
      (should (eq (org-truss-conclusion-position (org-truss-test--m model "Half the items repeat"))
                  'first))))
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
:TRUSS_ROLE: case
:END:
"
    (let ((model (org-truss-read)))
      (should (equal (org-truss-gaps (org-truss-test--m model "General"))
                     '((case . 1)))))))

(ert-deftest org-truss-test-usage-and-checks ()
  "What the structure shows, what it rests on, and what is left undone."
  (org-truss-test--with org-truss-test--file
    (let* ((model (org-truss-read))
           (checks (org-truss-checks model)))
      (should (equal (org-truss-test--labels (plist-get checks :unplaced))
                     '("Unused aside" "Lone remark")))
      (should (null (plist-get checks :grounds-only)))
      (should (equal (mapcar (lambda (g) (cons (org-truss-section-label (car g)) (mapcar #'car (cdr g))))
                             (plist-get checks :section-gaps))
                     '(("Structure" problem cause effect plan cost alternatives ask premises))))
      (should (equal (org-truss-test--labels (plist-get checks :bare))
                     '("A meeting that repeats itself can meet less")))
      (should (equal (org-truss-test--labels (plist-get checks :questions))
                     '("Who decides what is urgent")))
      (should (equal (org-truss-test--labels (plist-get checks :assumptions))
                     '("Items need a week to move")))
      (should (null (plist-get checks :unanswered)))
      (should (equal (mapcar (lambda (g) (org-truss-member-label (car g)))
                             (plist-get checks :gaps))
                     '("Move to fortnightly")))
      (should (equal (mapcar #'cdr (plist-get checks :broken)) '("none")))
      (should (null (plist-get checks :broken-grounds)))))
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
      (should (string-match-p "^Broken links -- links in a section" report))
      (should (string-match-p "^truss\\.org:[0-9]+: \\[\\[#none\\]\\] in Umbrella$" report))
      (should (string-match-p "^truss\\.org:[0-9]+: Move to fortnightly -- lacks TRUSS_ROLE minor (why › deduction)$"
                              report))
      (should (string-match-p "^truss\\.org:[0-9]+: Structure -- lacks TRUSS_ROLE problem cause " report))
      (should (string-match-p "^Not placed -- .*\ntruss\\.org:[0-9]+: Unused aside\ntruss\\.org:[0-9]+: Lone remark$"
                              report))
      (should (< (string-match "^Broken links" report) (string-match "^Assumptions" report)))
      (let ((line (and (string-match "^truss\\.org:\\([0-9]+\\): Lone remark$" report)
                       (string-to-number (match-string 1 report)))))
        (should (equal (progn (goto-char (point-min)) (forward-line (1- line))
                              (buffer-substring (point) (line-end-position)))
                       "** Lone remark")))))
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
"
    (should (equal (org-truss-check-report (org-truss-read) "f") "Nothing is left to do.\n"))))

(ert-deftest org-truss-test-convert-references ()
  "Links and grounds that name headings come to point by id, the member
named being given one; a heading no member has stays, broken."
  (org-truss-test--with (replace-regexp-in-string
                         "^- \\[\\[#\\(long\\|half\\)\\]"
                         (lambda (m) (if (equal (match-string 1 m) "long")
                                         "- [[*Reviews run long]" "- [[*Half the items repeat]"))
                         (replace-regexp-in-string
                          ":TRUSS_GROUNDS: \\[\\[#half\\]\\]"
                          ":TRUSS_GROUNDS: Half the items repeat; Lone remark; Nobody"
                          (replace-regexp-in-string ":CUSTOM_ID: half\n" "" org-truss-test--file)))
    (should (= (org-truss-convert-references-in-buffer) 4))
    (let* ((model (org-truss-read))
           (lone (org-truss-member-id (org-truss-test--m model "Lone remark")))
           (half (org-truss-member-id (org-truss-test--m model "Half the items repeat"))))
      (should (equal (list half lone) '("m1" "m2")))
      (should (equal (org-truss-member-grounds (org-truss-test--m model "Move to fortnightly"))
                     '("m1" "m2" "*Nobody")))
      (should (equal (org-truss-member-grounds (org-truss-test--m model "Half the items repeat"))
                     '("long")))
      (should (equal (org-truss-section-links (car (org-truss-section-children
                                                    (org-truss-model-structure model))))
                     '("long")))
      (should (string-match-p "^- \\[\\[#m1\\]\\]$" (buffer-string)))
      (should (string-match-p "as \\[\\[#long\\]\\] shows" (buffer-string))))
    (should (= (org-truss-convert-references-in-buffer) 0))))

(ert-deftest org-truss-test-any-logic-anywhere ()
  "Any cluster takes any logic pattern.  A section's asks for what the
sections right below it answer -- deeper down, a question is answered for
that section, not this one -- and its telling pattern's places are asked
for too.  A member's purpose asks its parts for the reader's questions."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** We move to fortnightly reviews
:PROPERTIES:
:TRUSS_LOGIC: report
:END:
*** Reviews run long
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
*** Hold them every other week
:PROPERTIES:
:TRUSS_ROLE: conclusion
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:TRUSS_LOGIC: explanation
:END:
** Now
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
** What we do
:PROPERTIES:
:TRUSS_ROLE: conclusion
:TRUSS_LOGIC: 5w1h
:TRUSS_TELLING: scqa
:END:
*** Why it is so
:PROPERTIES:
:TRUSS_ROLE: cause why
:END:
"
    (let* ((model (org-truss-read))
           (root (org-truss-model-structure model))
           (what (cadr (org-truss-section-children root)))
           (move (org-truss-test--m model "We move to fortnightly reviews"))
           (checks (org-truss-checks model)))
      (should (eq (org-truss-section-logic root) 'explanation))
      (should (equal (org-truss-gaps root) '((cause . 1) (premises . 1))))
      (should (equal (mapcar #'car (org-truss-gaps what))
                     '(who when where what how situation problem conclusion)))
      (should (equal (mapcar #'car (plist-get checks :section-gaps)) (list root what)))
      (should (equal (org-truss-gaps move) '((problem . 1) (cause . 1) (plan . 1))))
      (should (eq (org-truss-kind model (org-truss-test--m model "Reviews run long")) 'part))
      (should (equal (org-truss-role-label 'situation) "Situation"))
      (let ((org-truss-language 'ja))
        (should (equal (org-truss-role-label 'situation) "現状"))
        (should (equal (org-truss-role-label 'who) "誰が"))))))

(ert-deftest org-truss-test-grounds-only ()
  "A member reached only through grounds is in use but not shown."
  (org-truss-test--with "* M
:PROPERTIES:
:TRUSS_PART: members
:END:
** Shown
:PROPERTIES:
:CUSTOM_ID: shown
:TRUSS_GROUNDS: [[#behind]]
:END:
** Behind
:PROPERTIES:
:CUSTOM_ID: behind
:TRUSS_SOURCE: x
:END:
* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Only
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
- [[#shown]]
"
    (let ((checks (org-truss-checks (org-truss-read))))
      (should (equal (org-truss-test--labels (plist-get checks :grounds-only)) '("Behind")))
      (should (null (plist-get checks :unplaced))))))

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
      (should (equal (org-truss-member-label (org-truss-member-by-ref model "x")) "One")))))

;;;; Editing the structure

(ert-deftest org-truss-test-apply-structure-pattern ()
  "A section takes the place of the one new section it shares a question with,
as it is; the pattern adds the rest, and what fits no place stays at the end."
  (org-truss-test--with org-truss-test--file
    (org-truss-apply-structure-pattern (org-truss--part-pos "structure") 'problem-solving)
    (let* ((model (org-truss-read))
           (root (org-truss-model-structure model))
           (by-label (lambda (l) (seq-find (lambda (s) (equal (org-truss-section-label s) l))
                                           (org-truss-section-children root)))))
      (should (eq (org-truss-section-telling root) 'problem-solving))
      (should (equal (org-truss-test--section-labels root)
                     '("Sky" "Problem" "Cause" "Umbrella" "Plan" "Effect" "Rain")))
      (should (equal (org-truss-section-links (funcall by-label "Sky"))
                     '("long")))
      (should (equal (org-truss-section-links (funcall by-label "Umbrella"))
                     '("move" "none")))
      (should (equal (org-truss-section-roles (funcall by-label "Umbrella")) '(conclusion)))
      (should (equal (org-truss-section-roles (funcall by-label "Problem")) '(problem)))
      (should (equal (car (org-truss-section-public (funcall by-label "Rain"))) "Why it drags"))
      (should (equal (org-truss-section-links (funcall by-label "Rain"))
                     '("half"))))))

(ert-deftest org-truss-test-apply-pattern-fills-a-place-twice ()
  "Two sections answering the same question both take that place, in order."
  (org-truss-test--with "* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Now
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
** Then
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
"
    (org-truss-apply-structure-pattern (org-truss--part-pos "structure") 'sky-rain-umbrella)
    (let ((sections (org-truss-section-children (org-truss-model-structure (org-truss-read)))))
      (should (equal (mapcar #'org-truss-section-label sections)
                     '("Now" "Then" "Rain" "Umbrella")))
      ;; Sky, Rain, Umbrella is fact, interpretation, action.
      (should (equal (mapcar #'org-truss-section-roles sections)
                     '((situation) (situation) (interpretation) (conclusion)))))))

(ert-deftest org-truss-test-apply-pattern-keeps-a-nested-pattern ()
  "A section that takes a new one's place brings its own sections and pattern."
  (org-truss-test--with "* S
:PROPERTIES:
:TRUSS_PART: structure
:END:
** Umbrella
:PROPERTIES:
:TRUSS_ROLE: conclusion
:TRUSS_TELLING: sky-rain-umbrella
:END:
*** Sky
:PROPERTIES:
:TRUSS_ROLE: situation
:END:
- [[#inner]]
"
    (org-truss-apply-structure-pattern (org-truss--part-pos "structure") 'scqa)
    (let* ((root (org-truss-model-structure (org-truss-read)))
           (answer (nth 2 (org-truss-section-children root))))
      (should (equal (org-truss-section-label answer) "Umbrella"))
      (should (eq (org-truss-section-telling answer) 'sky-rain-umbrella))
      (should (equal (org-truss-section-links (car (org-truss-section-children answer)))
                     '("inner"))))))

(ert-deftest org-truss-test-unwrap ()
  "Unwrapping refuses to lose writing unless forced, and keeps every link."
  (org-truss-test--with org-truss-test--file
    (let ((root (org-truss--part-pos "structure")))
      (should (equal (org-truss-unwrap root) '("Rain")))
      (should (= 3 (length (org-truss-section-children
                            (org-truss-model-structure (org-truss-read))))))
      (should (null (org-truss-unwrap root t)))
      (let ((section (org-truss-model-structure (org-truss-read))))
        (should (null (org-truss-section-children section)))
        (should (null (org-truss-section-telling section)))
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
               ":TRUSS_ROLE: situation\n:END:\n#\\+begin_public\nWhere we are\\.\n#\\+end_public\n- \\[\\[#long"
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
:TRUSS_ROLE: ask
:END:
** Next
"
    (org-truss-add-link (org-truss-test--heading-pos "Empty") "A")
    (should (equal (plist-get (org-truss--own (org-truss-test--heading-pos "Empty")) :items)
                   '("A")))
    (should (equal (org-truss-section-roles
                    (car (org-truss-section-children (org-truss-model-structure (org-truss-read)))))
                   '(ask)))))

(ert-deftest org-truss-test-add-section ()
  "A new section goes last under its parent, with its roles."
  (org-truss-test--with org-truss-test--file
    (org-truss-add-section (org-truss--part-pos "structure") "Ask" '(ask))
    (let* ((root (org-truss-model-structure (org-truss-read)))
           (last (car (last (org-truss-section-children root)))))
      (should (equal (org-truss-section-label last) "Ask"))
      (should (equal (org-truss-section-roles last) '(ask))))))

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
      (should (memq (org-truss-member-by-ref model "half")
                    (org-truss-supports model (org-truss-test--m model "Move to fortnightly")))))
    (org-truss-rename (org-truss-test--heading-pos "Agendas repeat") "Agendas repeat")
    (should-error (org-truss-rename (org-truss-test--heading-pos "Agendas repeat") "Lone remark")
                  :type 'user-error)))

(ert-deftest org-truss-test-rename-keeps-tags ()
  "A tagged member keeps its tags when relabelled."
  (org-truss-test--with org-truss-test--file
    (org-truss-rename (org-truss-test--heading-pos "Items need a week to move") "Items are slow")
    (should (eq (org-truss-kind (org-truss-read)
                                (org-truss-test--m (org-truss-read) "Items are slow"))
                'assumption))))

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

(ert-deftest org-truss-test-skeleton ()
  "A new file has its parts and empty fields, headed in English whatever the
language; the guidance is in the language."
  (dolist (org-truss-language '(en ja))
    (org-truss-test--with (org-truss-skeleton "T")
      (let ((model (org-truss-read)))
        (should (equal (org-truss-model-title model) "T"))
        (should (eq (org-truss-section-logic (org-truss-model-structure model)) 'proposal))
        (should-not (string-match-p ":TRUSS_PURPOSE:" (buffer-string)))
        (should (string-prefix-p (concat "#+title: T\n\n" (org-truss--preamble) "\n* Brief\n")
                                 (buffer-string)))
        (should (equal (org-map-entries (lambda () (org-get-heading t t t t)))
                       '("Brief" "Reader" "Their question" "Response wanted" "Constraints"
                         "Subject" "Premises" "Issue" "Constraints" "Members" "Structure")))
        (should (string-match-p (if (eq org-truss-language 'ja)
                                    "^# この truss\\.org から文書を一つ作ります。"
                                  "^# This truss\\.org makes one document:")
                                (buffer-string)))
        (should (string-match-p (if (eq org-truss-language 'ja)
                                    "^この文書が満たすべき条件。"
                                  "^What the document must satisfy\\.")
                                (buffer-string)))
        (should (equal (mapcar #'car (org-truss-model-brief model))
                       '(reader question response constraints)))
        (should (equal (mapcar #'car (org-truss-model-subject model))
                       '(premises issue constraints)))
        (should (seq-every-p (lambda (f) (string-empty-p (cdr f)))
                             (append (org-truss-model-brief model)
                                     (org-truss-model-subject model))))
        (should (org-truss-model-structure model))
        (should (null (org-truss-model-members model)))))))

(ert-deftest org-truss-test-refresh-guides ()
  "Refreshing puts the current guidance back, adds it where it was deleted,
and leaves everything else as it was, a guide of your own included."
  (let ((org-truss-language 'ja))
    (org-truss-test--with "#+title: T

# An old preamble.

* 与件
:PROPERTIES:
:TRUSS_PART: brief
:END:
:GUIDE:
Old wording.
:END:
Notes on the brief.
** Reader
:PROPERTIES:
:TRUSS_FIELD: reader
:END:
The board.
** Mine
:PROPERTIES:
:TRUSS_FIELD: mine
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
        (should (string-prefix-p (concat "#+title: T\n\n" (org-truss--preamble) "\n* 与件\n") text))
        (should-not (string-match-p "Old wording\\|An old preamble" text))
        (should (string-match-p (concat ":END:\n:GUIDE:\nこの文書が満たすべき条件。\\(?:.*\n\\)*?:END:\n"
                                        "Notes on the brief\\.")
                                text))
        (should (string-match-p (concat ":TRUSS_FIELD: reader\n:END:\n:GUIDE:\n"
                                        "誰が読むか。.*\n:END:\nThe board\\.")
                                text))
        (should (string-match-p ":TRUSS_PART: members\n:END:\n:GUIDE:\n考えたこと：" text))
        (should (string-match-p ":GUIDE:\nMy own\\.\n:END:" text))
        (should (string-match-p ":GUIDE:\nNot a part's\\.\n:END:" text))
        (org-truss-refresh-guides-in-buffer)
        (should (equal (buffer-string) text))))))

(ert-deftest org-truss-test-subject-clusters ()
  "In the subject, a member whose pattern is how › parts sums up what is
nested under it, and holds as they do.  A member written there is what was
found, never a step or a part of what to do."
  (org-truss-test--with org-truss-test--clusters-file
    (let* ((model (org-truss-read))
           (head (org-truss-test--m model "The manager checks every driver before and after driving"))
           (part (org-truss-test--m model "The check may be made by video")))
      (should (eq (org-truss-member-home head) 'subject))
      (should (eq (org-truss-member-home (org-truss-test--m model "The rule may apply to us")) 'members))
      (should (org-truss-material-p part))
      (should (eq (org-truss-member-logic head) 'parts))
      (should (null (org-truss-member-logic part)))
      (should (eq (org-truss-kind model head) 'summary))
      (should (eq (org-truss-kind model part) 'fact))
      (should (equal (org-truss-test--labels (org-truss-supports model head))
                     '("The rule asks for a check before driving"
                       "The rule asks for a check after driving"
                       "The check may be made by video")))
      (should (eq (org-truss-kind model (org-truss-test--m model "The driver blows into the tester"))
                  'step)))))

(ert-deftest org-truss-test-logic-is-what-is-written ()
  "What is nested under a member is what its TRUSS_LOGIC says, wherever it is
written; with none, its support.  Nothing is read into it from the part: a
cluster of facts that does not say how › parts reads as an interpretation,
and the board says so."
  (org-truss-test--with (replace-regexp-in-string
                         ":CUSTOM_ID: rule\n:TRUSS_LOGIC: parts\n" ":CUSTOM_ID: rule\n"
                         org-truss-test--clusters-file)
    (let* ((model (org-truss-read))
           (head (org-truss-test--m model "The manager checks every driver before and after driving")))
      (should (null (org-truss-member-logic head)))
      (should (eq (org-truss-kind model head) 'claim))
      (should (string-match-p "no TRUSS_LOGIC.*how › parts"
                              (cdr (assq head (org-truss-misplaced model)))))))
  (should (eq (org-truss-default-logic 'subject) 'parts))
  (should (eq (org-truss-default-logic 'members) 'reasons)))

(ert-deftest org-truss-test-start-cluster ()
  "A member that starts a cluster is given its part's logic pattern, written
in the file; one already written stays."
  (org-truss-test--with org-truss-test--clusters-file
    (let ((plain (org-truss-test--heading-pos "The rule may apply to us")))
      (should (eq (org-truss-start-cluster plain 'members) 'reasons))
      (should (equal (org-entry-get plain "TRUSS_LOGIC") "reasons")))
    (let ((steps (org-truss-test--heading-pos "Drivers are checked before and after driving")))
      (should-not (org-truss-start-cluster steps 'members))
      (should (equal (org-entry-get steps "TRUSS_LOGIC") "steps")))
    (let ((fact (org-truss-test--heading-pos "A manager is named for five cars or more")))
      (should (eq (org-truss-start-cluster fact 'subject) 'parts)))))

(ert-deftest org-truss-test-subject-cluster-rests-on-its-parts ()
  "A claim standing on a summary rests on what its parts rest on."
  (org-truss-test--with (replace-regexp-in-string
                         "^\\(\\*\\*\\*\\* The check may be made by video\\)$" "\\1 :question:"
                         org-truss-test--clusters-file)
    (let ((model (org-truss-read)))
      (should (org-truss-hypothesis-p
               model (org-truss-test--m model "Drivers are checked before and after driving"))))))

(ert-deftest org-truss-test-misplaced ()
  "A fact among the members, or a question standing there alone, belongs in
the subject; an interpretation in the subject belongs among the members."
  (org-truss-test--with org-truss-test--clusters-file
    (let ((model (org-truss-read)))
      (should (equal (mapcar (lambda (c) (org-truss-member-label (car c)))
                             (org-truss-misplaced model))
                     '("The law binds us, so we must check" "The tester reads zero when sober")))
      (should (string-prefix-p "an interpretation"
                               (cdar (org-truss-misplaced model))))))
  (org-truss-test--with org-truss-test--file
    (let ((model (org-truss-read)))
      (should (equal (mapcar (lambda (c) (org-truss-member-label (car c)))
                             (org-truss-misplaced model))
                     '("Reviews run long" "Agenda diff" "Urgent items go to chat" "Unused aside"))))))

(ert-deftest org-truss-test-subject-checks ()
  "A cluster is met when anything in it is used; a question in the subject is
open whether or not anything uses it."
  (org-truss-test--with org-truss-test--clusters-file
    (let ((checks (org-truss-checks (org-truss-read))))
      (should (equal (org-truss-test--labels (plist-get checks :unmet))
                     '("The law binds us, so we must check")))
      (should (equal (org-truss-test--labels (plist-get checks :questions))
                     '("How many cars we run")))
      (should (equal (org-truss-test--labels (plist-get checks :unplaced))
                     '("The tester reads zero when sober"))))))

(provide 'org-truss-core-test)

;;; org-truss-core-test.el ends here

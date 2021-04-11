;;; -*- lexical-binding: t; -*-

(provide 'evergreen-configure)

(require 'cl-lib)

(require 'evergreen-view-task)
(require 'evergreen-view-patch)
(require 'evergreen-ui)
(require 'evergreen-api)

(defvar-local evergreen-configure-target-patch nil)
(defvar-local evergreen-configure-variants nil)

(cl-defstruct evergreen-configure-task name selected location parent)

(defun evergreen-configure-task-is-visible (task)
  (not (evergreen-configure-variant-collapsed (evergreen-configure-task-parent task))))

(defun evergreen-configure-task-face (task)
  (if (evergreen-configure-task-selected task)
      'evergreen-configure-task-selected
    'evergreen-configure-variant-unselected))

(defun evergreen-configure-task-insert (task)
  "Insert the given task into the buffer and mark its location."
  (insert
   (with-temp-buffer
     (insert "  ")
     (evergreen-configure-insert-checkbox (evergreen-configure-task-selected task))
     (insert " ")
     (insert (evergreen-configure-task-name task))
     (add-text-properties (point-min) (point-max) (list 'evergreen-configure-task task))
     (add-face-text-property (point-min) (point-max) (evergreen-configure-task-face task))
     (buffer-string)))
  (setf (evergreen-configure-task-location task) (evergreen-configure-make-marker)))

(defun evergreen-configure-task-set-selected (task selected)
  "Toggles whether the provided task is selcted or not. This must be called when the point is on
   the same line as the task."
  (let ((is-selected (evergreen-configure-task-selected task)))
    (when (not (eq selected is-selected))
      (setf (evergreen-configure-task-selected task) selected)
      (when-let ((location (evergreen-configure-task-location task)))
        (save-excursion
          (read-only-mode -1)
          (goto-char (marker-position location))
          (kill-line)
          (evergreen-configure-task-insert task)
          (read-only-mode)))
      (evergreen-configure-variant-update-nselected (evergreen-configure-task-parent task))))
  (when (evergreen-configure-task-location task) (forward-line)))

(cl-defstruct evergreen-configure-variant display-name name tasks collapsed location)

(defun evergreen-configure-variant-nselected-tasks (variant)
  (length (evergreen-configure-variant-selected-tasks variant)))

(defun evergreen-configure-variant-selected-tasks (variant)
  (seq-filter
   'evergreen-configure-task-selected
   (evergreen-configure-variant-tasks variant)))

(defun evergreen-configure-variant-face (variant)
  "Get the face for a given variant line depending on the number of selected tasks for that variant."
  (let ((nselected (evergreen-configure-variant-nselected-tasks variant)))
    (if (> nselected 0)
        (if (= nselected (length (evergreen-configure-variant-tasks variant))) 'success 'warning)
      '('evergreen-configure-variant-unselected . 'bold))))

(defun evergreen-configure-variant-insert (variant)
  "Insert a variant line into the configure buffer."
  (insert
   (propertize
    (concat
     (if (evergreen-configure-variant-collapsed variant) "⮞" "⮟")
     " "
     (evergreen-configure-variant-display-name variant)
     (format
      " (%d/%d)"
      (evergreen-configure-variant-nselected-tasks variant)
      (length (evergreen-configure-variant-tasks variant))))
    'evergreen-configure-variant variant
    'face (evergreen-configure-variant-face variant)
    'rear-nonsticky t))
  (setf (evergreen-configure-variant-location variant) (evergreen-configure-make-marker)))

(defun evergreen-configure-variant-set-selected (variant selected)
  (seq-do
   (lambda (task)
     (evergreen-configure-task-set-selected task selected))
   (evergreen-configure-variant-tasks variant))
  (forward-line))

(defun evergreen-configure-variant-parse (data scheduled-tasks)
  "Parse a configure-variant from the given data, using the provided alist of display-name to evergreen-task-info
   to determine pre-selected tasks."
  (let*
      ((variant-scheduled-tasks (or (cdr (assoc-string (gethash "displayName" data) scheduled-tasks)) '()))
       (variant
        (make-evergreen-configure-variant
         :display-name (gethash "displayName" data)
         :name (gethash "name" data)
         :tasks (seq-map (lambda (task-name)
                           (make-evergreen-configure-task
                            :name task-name
                            :selected (seq-some
                                       (lambda (task)
                                         (string= task-name (evergreen-task-info-display-name task)))
                                       variant-scheduled-tasks)
                            :location nil
                            :parent nil))
                         (gethash "tasks" data))
         :collapsed t
         :location nil)))
    (seq-do
     (lambda (task)
       (setf (evergreen-configure-task-parent task) variant))
     (evergreen-configure-variant-tasks variant))
    variant))

(defun evergreen-configure-variant-update-nselected (variant)
  "Update the number of selected variants displayed on the variant line."
  (save-excursion 
    (read-only-mode -1)
    (goto-char (marker-position (evergreen-configure-variant-location variant)))
    (kill-line)
    (evergreen-configure-variant-insert variant)
    (read-only-mode)))

(defun evergreen-configure-make-marker ()
  "Make a marker that is at the beginning of the current line and updates properly in response to insertion."
  (let ((marker (make-marker)))
    (set-marker marker (line-beginning-position))
    (set-marker-insertion-type marker t)
    marker))

(defun evergreen-configure-insert-checkbox (is-selected)
  (insert
   (propertize
    (concat "[" (if is-selected "✔" " ") "]")
    'face 'org-checkbox)))

(defun evergreen-configure-patch-data (patch-data)
  (evergreen-configure-patch (evergreen-patch-parse patch-data) '()))

(defun evergreen-configure-patch (patch scheduled-tasks)
  "Switch to a configuration buffer for the given evergreen-patch struct using the provided alist of display-name
   to evergreen-task-info to determine pre-scheduled tasks"
  (switch-to-buffer (get-buffer-create (format "evergreen-configure: %S" (evergreen-patch-description patch))))
  (read-only-mode -1)
  (evergreen-configure-mode)
  (erase-buffer)
  (setq-local evergreen-configure-target-patch patch)

  (evergreen-ui-insert-header
   (list
    (cons "Description" (evergreen-patch-description patch))
    (cons "Patch Number" (number-to-string (evergreen-patch-number patch)))
    (cons "Status" (evergreen-status-text (evergreen-patch-status patch)))
    (cons "Created at" (evergreen-date-string (evergreen-patch-create-time patch))))
   "Configure Patch")

  (newline)
  (setq-local evergreen-configure-variants
              (seq-map
               (lambda (variant-data)
                 (let ((variant (evergreen-configure-variant-parse variant-data scheduled-tasks)))
                   (evergreen-configure-variant-insert variant)
                   (newline)
                   variant))
               (evergreen-get-patch-variants (evergreen-patch-id patch))))
  (read-only-mode)
  (goto-char (point-min)))

(defun evergreen-configure-current-variant ()
  (get-text-property (point) 'evergreen-configure-variant))

(defun evergreen-configure-current-task ()
  (get-text-property (point) 'evergreen-configure-task))

(defun evergreen-configure-toggle-current-variant ()
  "Toggles the section at point"
  (interactive)
  (when-let ((variant (evergreen-configure-current-variant)))
    (read-only-mode -1)
    (save-excursion
      (setf (evergreen-configure-variant-collapsed variant) (not (evergreen-configure-variant-collapsed variant)))
      (if (evergreen-configure-variant-collapsed variant)
          (progn
            (forward-line)
            (seq-do
             (lambda (task)
               (setf (evergreen-configure-task-location task) nil)
               (kill-whole-line))
             (evergreen-configure-variant-tasks variant)))
        (forward-line)
        (seq-do
         (lambda (task)
           (evergreen-configure-task-insert task)
           (newline))
         (evergreen-configure-variant-tasks variant)))
      (goto-char (marker-position (evergreen-configure-variant-location variant)))
      (kill-line)
      (evergreen-configure-variant-insert variant))
    (read-only-mode)))

(defun evergreen-configure-set-select-at-point (selected)
  "Toggles the section at point"
  (if-let ((task (evergreen-configure-current-task)))
      (progn
        (evergreen-configure-task-set-selected task selected))
    (when-let ((variant (evergreen-configure-current-variant)))
        (evergreen-configure-variant-set-selected variant selected))))

(defun evergreen-configure-select-at-point ()
  (interactive)
  (evergreen-configure-set-select-at-point t))

(defun evergreen-configure-deselect-at-point ()
  (interactive)
  (evergreen-configure-set-select-at-point nil))

(defun evergreen-configure-schedule ()
  (interactive)
  (if-let
      ((selected-variants
        (seq-filter
         (lambda (variant) (> (evergreen-configure-variant-nselected-tasks variant) 0))
         evergreen-configure-variants)))
      (progn
        (message "Scheduling patch...")
        (evergreen-api-post
         (format "patches/%s/configure" (evergreen-patch-id evergreen-configure-target-patch))
         (lambda (_) (evergreen-view-patch evergreen-configure-target-patch))
         (json-encode
          (list
           (cons "description" (evergreen-patch-description evergreen-configure-target-patch))
           (cons
            "variants"
            (seq-map
             (lambda (variant)
               (list
                (cons "id" (evergreen-configure-variant-name variant))
                (cons "tasks"
                      (seq-map 'evergreen-configure-task-name (evergreen-configure-variant-selected-tasks variant)))))
             selected-variants))))))))

(defun evergreen-get-patch-variants (patch-id)
  "Get list of variants and their associated tasks for the given patch."
  (let ((data
         (evergreen-api-graphql-request
          (format "{ patch(id: \"%s\") { project { variants { displayName,name,tasks }}}}" patch-id))))
    (gethash "variants" (gethash "project" (gethash "patch" data)))))

(defvar evergreen-configure-mode-map nil "Keymap for evergreen-configure buffers")

(progn
  (setq evergreen-configure-mode-map (make-sparse-keymap))
  (when (require 'evil nil t)
    (evil-define-key 'normal evergreen-configure-mode-map
      (kbd "<tab>") 'evergreen-configure-toggle-current-variant
      (kbd "m") 'evergreen-configure-select-at-point
      (kbd "u") 'evergreen-configure-deselect-at-point
      (kbd "x") 'evergreen-configure-schedule
      (kbd "r") (lambda ()
                  (interactive)
                  (evergreen-configure-patch evergreen-configure-target-patch '()))))

  (define-key evergreen-configure-mode-map (kbd "<tab>") 'evergreen-configure-toggle-current-variant)
  (define-key evergreen-configure-mode-map (kbd "m") 'evergreen-configure-select-at-point)
  (define-key evergreen-configure-mode-map (kbd "u") 'evergreen-configure-deselect-at-point)
  (define-key evergreen-configure-mode-map (kbd "x") 'evergreen-configure-schedule)

  (define-key evergreen-configure-mode-map (kbd "r") (lambda ()
                                                             (interactive)
                                                             (evergreen-configure-patch evergreen-configure-target-patch '())))
  )

(define-derived-mode
  evergreen-configure-mode
  fundamental-mode
  "Evergreen"
  "Major mode for evergreen-configure buffer")
  
(defface evergreen-configure-variant-unselected
  '((t (:inherit 'shadow)))
  "The face to use for variants that have no selected tasks"
  :group 'evergreen)

(defface evergreen-configure-task-selected
  '((t (:inherit 'success :bold nil)))
  "The face to use for a task that has been selected"
  :group 'evergreen)

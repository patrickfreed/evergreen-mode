;;; -*- lexical-binding: t; -*-

(provide 'evergreen-view-task)

(require 'cl-lib)

(cl-defstruct evergreen-task
  id
  display-name
  start-time
  finish-time
  status
  all-log
  task-log
  agent-log
  system-log
  event-log)

(defun evergreen-task-parse (data)
  (let ((logs (alist-get 'logs data)))
    (make-evergreen-task
     :id (alist-get 'task_id data)
     :display-name (alist-get 'display_name data)
     :start-time (alist-get 'start_time data)
     :finish-time (alist-get 'finish_time data)
     :status (alist-get 'status data)
     :all-log (alist-get 'all_log logs)
     :task-log (alist-get 'task_log logs)
     :agent-log (alist-get 'agent_log logs)
     :system-log (alist-get 'system_log logs)
     :event-log (alist-get 'event_log logs))))

(defun evergreen-get-task (task-id)
  (evergreen-task-parse (evergreen-get-p (format "tasks/%s" task-id))))

(defface evergreen-view-task-title
  '((t
     :bold t
     :italic t
     :underline t
     :height 1.5))
  "view task title face")

(defun evergreen-view-task-header-line (property value)
  (format
   "%-16s%s"
   (with-temp-buffer
     (insert (format "%s:" property))
     (add-text-properties (point-min) (point-max) (list 'face 'bold))
     (buffer-string))
   (with-temp-buffer
     (setq fill-column (- (window-width) 26))
     (setq fill-prefix (make-string 16 ? ))
     (insert value)
     (fill-paragraph)
     (buffer-string))))

(defun evergreen-view-task-refresh ()
  (interactive)
  (evergreen-view-task
   (evergreen-task-id evergreen-current-task) evergreen-build-variant))

(defun evergreen-view-task-back-to-patch ()
  (interactive)
  (switch-to-buffer evergreen-task-buffer))

(defun evergreen-view-task (task-id build-variant previous-buffer)
  (switch-to-buffer (get-buffer-create (format "evergreen-view-task: %S" task-id)))
  (read-only-mode -1)
  (evergreen-view-task-mode)
  (erase-buffer)
  (setq-local evergreen-build-variant build-variant)
  (setq-local evergreen-current-task (evergreen-get-task task-id))
  (setq-local evergreen-task-buffer previous-buffer)
  (let ((task evergreen-current-task) (build-variant evergreen-build-variant))
    (insert
     (with-temp-buffer
       (insert (format "%s on %s"
                       (evergreen-task-display-name task)
                       build-variant))
       (add-text-properties (point-min) (point-max) (list 'face 'evergreen-view-task-title))
       (buffer-string)))
    (newline)
    (insert (evergreen-view-task-header-line "Status" (evergreen-status-text (evergreen-task-status task))))
    (newline)
    (insert (evergreen-view-task-header-line "Started at" (evergreen-task-start-time task)))
    (newline 2))
  (insert (evergreen-get-string (format "%s&text=true" (evergreen-task-task-log evergreen-current-task))))
  (read-only-mode)
  (goto-line 0)
  )

(defvar evergreen-view-task-mode-map nil "Keymap for evergreen-view-task buffers")

(progn
  (setq evergreen-view-task-mode-map (make-sparse-keymap))

  (define-key evergreen-view-task-mode-map (kbd "<backtab>") 'evergreen-view-task-back-to-patch)
  (define-key evergreen-view-task-mode-map (kbd "r") 'evergreen-view-task-refresh)

  (define-key evergreen-view-task-mode-map (kbd "h") 'backward-char)
  (define-key evergreen-view-task-mode-map (kbd "j") 'next-line)
  (define-key evergreen-view-task-mode-map (kbd "k") 'previous-line)
  (define-key evergreen-view-task-mode-map (kbd "l") 'forward-char)
  )

(define-derived-mode
  evergreen-view-task-mode
  fundamental-mode
  "Evergreen"
  "Major mode for evergreen-view-task buffer")
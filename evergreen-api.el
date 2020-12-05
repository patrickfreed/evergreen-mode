(provide 'evergreen-api)

(defun evergreen-api-init ()
  "Load credentials from ~/.evergreen.yml if unset.
   This function may be invoked repeatedly, all but the first
   invocation are no-ops."
  (if (not (boundp 'evergreen-api-key))
      (with-temp-buffer
        (insert-file-contents "~/.evergreen.yml")
        (goto-char (point-min))
        (if (search-forward-regexp "api_key: \"?\\([a-z0-9]*\\)\"?$")
            (setq evergreen-api-key (match-string 1))
          (error "api key not included in ~/.evergreen.yml"))
        (goto-char (point-min))
        (if (search-forward-regexp "user: \"?\\(.*\\)\"?$")
            (setq evergreen-user (match-string 1))
          (error "api user not included in ~/.evergreen.yml"))
        )))

(defun evergreen-read-project-name ()
  "Get the project name from user input, defaulting to the current projectile project.
   This requires projectile."
  (or
   (and (boundp 'evergreen-project-name) evergreen-project-name)
   (let*
       ((default-project-name
          (if-let ((name-projectile (projectile-project-name)))
              (if (string= name-projectile "-")
                  (error "not in a projectile-project")
                name-projectile)))
        (prompt
         (cond
          (default-project-name (format "Project name (%s): " default-project-name))
          (t "Project name: "))))
     (if (or evergreen-always-prompt-for-project-name (not default-project-name))
         (read-string prompt nil nil default-project-name)
       default-project-name))))

(defun evergreen-api-get-async (url success-callback &optional params)
  (request
    (concat "https://evergreen.mongodb.com/api/rest/v2/" url)
    :headers (list (cons "Api-User" evergreen-user) (cons "Api-Key" evergreen-api-key))
    :params params
    :success success-callback
    :parser 'json-read))
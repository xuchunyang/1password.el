;;; 1password.el --- Retrive password from 1Password  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Xu Chunyang

;; Author: Xu Chunyang <mail@xuchunyang.me>
;; Homepage: https://github.com/xuchunyang/1password.el
;; Package-Requires: ((emacs "25.1"))
;; Created: 2019年5月15日 晚饭后

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package needs the command op, it is the 1Password command line tool
;; <https://support.1password.com/command-line/>.

;;; Code:

(defgroup 1password nil
  "Use 1Password from Emacs."
  :group 'tools)

(defcustom 1password-op-executable "op"
  "The 1Password command-line tool."
  :group '1password
  :type 'string)

(defvar 1password-token nil
  "Session token automatically expires after 30 minutes of inactivity.")

;;;###autoload
(defun 1password-login (password)
  (interactive (list (read-passwd "1Password Master Password: ")))
  (unless (file-exists-p "~/.op/config")
    (user-error "Please sign in from the command line for the first time, \
see https://support.1password.com/command-line-getting-started/#get-started-with-the-command-line-tool"))
  (with-temp-buffer
    (if (zerop (call-process-shell-command (format "echo -n %s | %s signin" password 1password-op-executable) nil t))
        (setq 1password-token (buffer-string))
      (error "'op login' failed: %s" (buffer-string)))))

(defvar 1password-items nil)

(defun 1password--json-read ()
  (let ((json-object-type 'alist)
        (json-array-type  'list)
        (json-key-type    'symbol)
        (json-false       nil)
        (json-null        nil))
    (json-read)))

(defun 1password-items ()
  "Cache of 'op list items'."
  (or 1password-items
      (with-temp-buffer
        (if (zerop (call-process 1password-op-executable nil t nil "list" "items" (concat "--session=" 1password-token)))
            (progn
              (goto-char (point-min))
              (setq 1password-items (1password--json-read)))
          (error "'op list items' failed: %s" (buffer-string))))))

(defun 1password--read-name ()
  (let ((completion-ignore-case t))
    (completing-read "Name: "
                     (mapcar (lambda (item) (let-alist item .overview.title))
                             (1password-items))
                     nil t)))

(defvar 1password--get-item-cache nil
  "Cache for `1password-get-item'.

1Password is soooooo slow from here.")

(defun 1password-get-item (name)
  "Return json object for the NAME item."
  (or (assoc-string name 1password--get-item-cache 'ignore-case)
      (with-temp-buffer
        (if (zerop (call-process 1password-op-executable nil t nil "get" "item" name (concat "--session=" 1password-token)))
            (progn
              (goto-char (point-min))
              (let ((item (1password--json-read)))
                (push (cons (downcase name) item) 1password--get-item-cache)
                item))
          (error "'op list items' failed: %s" (buffer-string))))))

;;;###autoload
(defun 1password-get-password (name &optional copy)
  "Return password of the NAME item."
  (interactive (list (1password--read-name) t))
  (when (string= "" name)
    (user-error "Name can't be emtpy"))
  (catch 'getpass
    (dolist (field (let-alist (1password-get-item name) .details.fields))
      (let-alist field
        (when (string= .name "password")
          (when copy
            (kill-new .value)
            (message "Password of %s copied: %s" name .value))
          (throw 'getpass .value))))))

(provide '1password)
;;; 1password.el ends here

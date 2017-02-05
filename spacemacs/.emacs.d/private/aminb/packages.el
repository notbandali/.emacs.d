;;; packages.el --- aminb layer packages file for Spacemacs.
;;
;; Copyright (c) 2016 Amin Bandali
;;
;; Author: Amin Bandali <amin@aminb.org>
;; URL: https://github.com/aminb/dotfiles
;;
;; This file is not part of GNU Emacs.
;;
;;; License: GPLv3

;;; Commentary:

;; This file is a collection of my settings and customizations on top of
;; spacemacs.

;;; Code:

(defconst aminb-packages
  '(counsel
    creamsody-theme
    crux
    ;; mu4e has to be installed manually,
    ;; and make sure it's in load-path
    (mu4e :location site)
    smtpmail
    writeroom-mode
    znc)
  "The list of Lisp packages required by the aminb layer.")

(defun aminb/post-init-counsel ()
  (use-package counsel
    :defer t
    :config
    (progn
      (spacemacs/set-leader-keys-for-major-mode 'eshell-mode
        "," 'counsel-esh-history)
      (add-hook 'eshell-mode-hook
                '(lambda () (define-key eshell-mode-map
                              (kbd "M-l") 'counsel-esh-history)))
      )))

(defun aminb/init-creamsody-theme ())

(defun aminb/init-crux ()
    (use-package crux
      :defer t
      :bind (("C-c d" . crux-duplicate-current-line-or-region)
             ("C-c M-d" . crux-duplicate-and-comment-current-line-or-region)
             )))

(defun aminb/init-writeroom-mode ()
  (use-package writeroom-mode             ; Distraction-free editing
    :defer t
    :config (setq writeroom-width 82)
    :bind (("C-c W" . writeroom-mode)
           ("s-?" . writeroom-toggle-mode-line))))

(defun aminb/init-znc ()
  (use-package znc
    :defer t
    :init
    (spacemacs/set-leader-keys
      "aiz" 'znc-erc)
    :config
    (progn
      ;; Set the erc nick completion postfix to ", "
      (setq erc-pcomplete-nick-postfix ", ")

      ;; Restore channel buffers from logs
      (setq erc-log-insert-log-on-open t)

      ;;; (BEGIN) work around log restoration bug
      ;;  taken from https://www.emacswiki.org/emacs/ErcLogging

      ;; ;;; Original version in the Emacs sources:
      ;; (defun erc-log-all-but-server-buffers (buffer)
      ;;   "Returns t if logging should be enabled in BUFFER.
      ;; Returns nil if `erc-server-buffer-p' returns t."
      ;;   (save-excursion
      ;;     (save-window-excursion
      ;;       (set-buffer buffer)
      ;;       (not (erc-server-buffer-p)))))

      ;; My version:
      (defun erc-log-all-but-server-buffers (buffer)
        (with-current-buffer buffer
          (not (erc-server-buffer-p))))
      ;;
      ;; ;;; Anyway, a more direct modification also works fine:
      ;; (defun erc-log-all-but-server-buffers (buffer)
      ;;  (set-buffer buffer)
      ;;  (not (erc-server-buffer-p)))
      ;;; (END)

      (require 'notifications)
      (defun erc-global-notify (match-type nick message)
        "Notify when a message is recieved."
        (notifications-notify
         :title nick
         :body message
         ;; :app-icon (concat spacemacs-assets-directory "spacemacs.svg")
         :urgency 'normal))

      (defun vbe:znc-add-server (server port user networks)
        "Add a server to the list of ZNC servers.
We use SSL inconditionaly. Moreover, we don't store the password
but put nil instead. At least, we tweak the username to contain
the network name later, this will be separated again."
        (add-to-list 'znc-servers
                     (list server
                           port
                           t                  ; SSL enabled
                           (mapcar (function (lambda (slug) (list slug
                                                                  (format "%s/%s" user slug)
                                                                  nil)))
                                   networks))))

      (defun vbe:znc-erc-ssl-connector (&rest R)
        "Connect to ERC using SSL and retrieve password with `auth-source-search'.
Moreover, handle multiple networks by sending the password with
the appropriate network slug that we extract from the nick."
        (let* ((user (nth 0 (split-string (plist-get R :nick) "/")))
               (slug (nth 1 (split-string (plist-get R :nick) "/")))
               (found (nth 0 (auth-source-search :host (plist-get R :server)
                                                 :user user
                                                 :require '(:user :secret)
                                                 :max 1))))
          (if found
              (let ((password (let ((secret (plist-get found :secret)))
                                (if (functionp secret)
                                    (funcall secret)
                                  secret))))
                (plist-put R :password (format "%s/%s:%s" user slug password))
                (plist-put R :nick user)
                (apply 'erc-tls R)))))
      (setq znc-erc-ssl-connector 'vbe:znc-erc-ssl-connector)

      ;; Define networks
      (vbe:znc-add-server "nix.aminb.org" 6669 "amin"
                          '(freenode mozilla))

      ;; https://www.emacswiki.org/emacs/ErcBar
      ;; Display a bar before unread messages
      (eval-after-load 'erc-track
        '(progn
           (defun erc-bar-move-back (n)
             "Moves back n message lines. Ignores wrapping, and server messages."
             (interactive "nHow many lines ? ")
             (re-search-backward "^.*<.*>" nil t n))

           (defun erc-bar-update-overlay ()
             "Update the overlay for current buffer, based on the content of
erc-modified-channels-alist. Should be executed on window change."
             (interactive)
             (let* ((info (assq (current-buffer) erc-modified-channels-alist))
                    (count (cadr info)))
               (if (and info (> count erc-bar-threshold))
                   (save-excursion
                     (end-of-buffer)
                     (when (erc-bar-move-back count)
                       (let ((inhibit-field-text-motion t))
                         (move-overlay erc-bar-overlay
                                       (line-beginning-position)
                                       (line-end-position)
                                       (current-buffer)))))
                 (delete-overlay erc-bar-overlay))))

           (defvar erc-bar-threshold 1
             "Display bar when there are more than erc-bar-threshold unread messages.")
           (defvar erc-bar-overlay nil
             "Overlay used to set bar")
           (setq erc-bar-overlay (make-overlay 0 0))
           (overlay-put erc-bar-overlay 'face '(:underline "purple"))
           ;;put the hook before erc-modified-channels-update
           (defadvice erc-track-mode (after erc-bar-setup-hook
                                            (&rest args) activate)
             ;;remove and add, so we know it's in the first place
             (remove-hook 'window-configuration-change-hook 'erc-bar-update-overlay)
             (add-hook 'window-configuration-change-hook 'erc-bar-update-overlay))
           (add-hook 'erc-send-completed-hook (lambda (str)
                                                (erc-bar-update-overlay)))))

      )))

(defun aminb/post-init-mu4e ()
  (setq maildir "~/mail")
  (use-package mu4e
    :defer t
    :config
    (progn
      (setq mu4e-maildir maildir
            mu4e-get-mail-command "true"
            mu4e-update-interval 300
            mu4e-view-show-addresses t
            mu4e-headers-include-related t
            mu4e-enable-notifications t
            mu4e-enable-mode-line t
            mu4e-compose-signature-auto-include t
            mu4e-compose-signature
            (concat
             "Amin Bandali\n"
             "<aminb.org>\n")
            message-kill-buffer-on-exit t ; don't keep message buffers around
            mu4e-attachment-dir "~/dls"
            mu4e-sent-folder "/amin/Sent"
            mu4e-drafts-folder "/amin/Drafts"
            mu4e-trash-folder "/amin/Trash"
            user-full-name "Amin Bandali"
            user-mail-address "amin@aminb.org"
            mu4e-view-html-plaintext-ratio-heuristic most-positive-fixnum
            mu4e-context-policy 'pick-first
            mu4e-contexts
              (list (make-mu4e-context
                     :name "Personal"
                     :enter-func (lambda () (mu4e-message "Switch to the Personal context"))
                     :match-func (lambda (msg)
                                   (when msg
                                     (s-prefix? "/amin/" (mu4e-message-field msg :maildir))))
                     :vars '((user-mail-address . "amin@aminb.org")
                             (mu4e-sent-folder . "/amin/Sent")
                             (mu4e-drafts-folder . "/amin/Drafts")
                             (mu4e-trash-folder . "/amin/Trash")
                             (mu4e-sent-messages-behavior . sent)
                             (smtpmail-default-smtp-server . "nix.aminb.org")
                             (smtpmail-smtp-server . "nix.aminb.org")
                             (smtpmail-stream-type . starttls)
                             (smtpmail-smtp-service . 587)))
                    (make-mu4e-context
                     :name "BB"
                     :enter-func (lambda () (mu4e-message "Switch to the BB context"))
                     :match-func (lambda (msg)
                                   (when msg
                                     (s-prefix? "/gmail/" (mu4e-message-field msg :maildir))))
                     :vars '((user-mail-address . "amin.bandali@gmail.com")
                             (mu4e-sent-folder . "/gmail/Sent")
                             (mu4e-drafts-folder . "/gmail/Drafts")
                             (mu4e-trash-folder . "/gmail/Trash")
                             (mu4e-sent-messages-behavior . delete)
                             (mu4e-compose-signature . nil)
                             (smtpmail-default-smtp-server . "smtp.gmail.com")
                             (smtpmail-smtp-server . "smtp.gmail.com")
                             (smtpmail-stream-type . starttls)
                             (smtpmail-smtp-service . 587)))
                     (make-mu4e-context
                      :name "GNU"
                      :enter-func (lambda () (mu4e-message "Switch to the GNU context"))
                      :match-func (lambda (msg)
                                    (when msg
                                      (s-prefix? "/gnu/" (mu4e-message-field msg :maildir))))
                      :vars '((user-mail-address . "aminb@gnu.org")
                              (mu4e-sent-folder . "/gnu/Sent")
                              (mu4e-drafts-folder . "/gnu/Drafts")
                              (mu4e-trash-folder . "/gnu/Trash")
                              (mu4e-sent-messages-behavior . sent)
                              (smtpmail-default-smtp-server . "fencepost.gnu.org")
                              (smtpmail-smtp-server . "fencepost.gnu.org")
                              (smtpmail-stream-type . starttls)
                              (smtpmail-smtp-service . 587)))))
      (with-eval-after-load 'mu4e-alert
        ;; Enable Desktop notifications
        (mu4e-alert-set-default-style 'notifications))))

  (use-package gnus-dired
    ;; A special version of the gnus-dired-mail-buffers function
    ;; that understands mu4e buffers as well.
    ;; Usage: mark the file(s) in dired and press C-c RET C-a,
    ;; then will be asked whether to attach them to an existing
    ;; message, or create a new one.
    :defer t
    :config
    (progn
      ;; make the `gnus-dired-mail-buffers' function also work on
      ;; message-mode derived modes, such as mu4e-compose-mode
      (defun gnus-dired-mail-buffers ()
        "Return a list of active message buffers."
        (let (buffers)
          (save-current-buffer
            (dolist (buffer (buffer-list t))
              (set-buffer buffer)
              (when (and (derived-mode-p 'message-mode)
                         (null message-sent-message-via))
                (push (buffer-name buffer) buffers))))
          (nreverse buffers)))
      (setq gnus-dired-mail-mode 'mu4e-user-agent)
      (add-hook 'dired-mode-hook 'turn-on-gnus-dired-mode))
    )

  ;; Exclude the files in maildir from recents
  (use-package recentf
    :defer t
    :config
    (add-to-list 'recentf-exclude (expand-file-name maildir)))

  (spacemacs/set-leader-keys
    "am" 'mu4e)
  )

(defun aminb/init-smtpmail ()
  (use-package smtpmail
    :defer t
    :config
    (setq smtpmail-default-smtp-server "nix.aminb.org"
          smtpmail-local-domain "aminb.org"
          smtpmail-smtp-server "nix.aminb.org"
          smtpmail-stream-type 'starttls
          smtpmail-smtp-service 587
          send-mail-function 'smtpmail-send-it)))

;;; packages.el ends here
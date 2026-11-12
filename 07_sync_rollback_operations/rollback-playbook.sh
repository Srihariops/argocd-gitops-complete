#!/bin/sh
# ======================================================================
# FILE   : rollback-playbook.sh
# PURPOSE: Three rollback methods with commands.
# APPLY  : read, then run the one you need
# ======================================================================
# Three rollback methods. Pick by situation.

# ---------- METHOD 1 (BEST): Git revert. Git stays the truth. Works with auto-sync ON ----------
git log --oneline -5                                   # find the bad commit
git revert <bad-sha> && git push                       # Argo CD deploys the previous state
# If Image Updater wrote the bad tag, revert ITS commit (message "build: automatic update ...").
# To stop it from moving forward again, pin the tag (allowTags / ignoreTags) or pause the ImageUpdater.

# ---------- METHOD 2: Argo CD rollback (emergency). Auto-sync must be OFF first ----------
argocd app set <app> --sync-policy none
argocd app history <app>
argocd app rollback <app> <ID>
# ...then fix Git, then turn auto-sync back on:
argocd app set <app> --sync-policy automated --auto-prune --self-heal

# ---------- METHOD 3: Pin a known-good revision (no Git change) ----------
argocd app set <app> --revision <good-tag-or-sha>      # app now follows that revision
# later set it back:  argocd app set <app> --revision main

# ---------- Argo Rollouts users ----------
# kubectl argo rollouts abort <rollout>   |   kubectl argo rollouts undo <rollout>

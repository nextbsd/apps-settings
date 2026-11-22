# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Installs an app under the name people see when gnustep-make can't build
# it under that name (one with a space or "&", since gnustep-make names
# its variables after the app). Set INSTALL_NAME, then include this after
# application.make:
#
#   INSTALL_NAME = Date & Time
#   include ../Shared/InstallName.make
#
# GNUSTEP_APPS already starts with DESTDIR when one is given, so this
# works for a staged install (gmake install DESTDIR=...) too. The link
# gnustep-make puts in GNUSTEP_TOOLS for the app is pointed at the
# renamed bundle.

INSTALLED_APPS = $(GNUSTEP_APPS)
INSTALLED_TOOL_LINK = $(GNUSTEP_TOOLS)/$(GNUSTEP_TARGET_LDIR)/$(APP_NAME)

after-install::
	rm -rf "$(INSTALLED_APPS)/$(INSTALL_NAME).app"
	mv "$(INSTALLED_APPS)/$(APP_NAME).app" "$(INSTALLED_APPS)/$(INSTALL_NAME).app"
	@if [ -L "$(INSTALLED_TOOL_LINK)" ]; then \
		target=`readlink "$(INSTALLED_TOOL_LINK)"`; \
		ln -sfn "$${target%/$(APP_NAME).app/$(APP_NAME)}/$(INSTALL_NAME).app/$(APP_NAME)" \
		    "$(INSTALLED_TOOL_LINK)"; \
	fi

after-uninstall::
	rm -rf "$(INSTALLED_APPS)/$(INSTALL_NAME).app"

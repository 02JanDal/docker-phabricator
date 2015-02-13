FROM debian:jessie

MAINTAINER Yvonnick Esnault <yvonnick@esnau.lt>

ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true

RUN apt-get update

RUN apt-get install -y wget less zip cron sudo dpkg supervisor

RUN apt-get install -y mysql-server mysql-client libmysqlclient-dev apache2
#RUN service apache2 stop

RUN apt-get install -y php5 libapache2-mod-php5 php5-mcrypt php5-mysql \
	php5-gd php5-dev php5-curl php5-cli php5-json php5-ldap php5-apcu

RUN apt-get install -y git subversion mercurial python-pygments

RUN apt-get install -y openssh-server openssh-client

RUN cd /opt/ && \
	git clone https://github.com/phacility/libphutil.git && \
	git clone https://github.com/phacility/arcanist.git && \
	git clone https://github.com/phacility/phabricator.git

RUN apt-get install python-pygments

RUN useradd daemon-user && useradd -m vcs && \
	usermod -a -G sudo daemon-user && \
	echo 'vcs ALL=(daemon-user) SETENV: NOPASSWD: /usr/bin/git-upload-pack, /usr/bin/git-receive-pack, /usr/bin/hg, /usr/bin/svnserve' >> /etc/sudoers && \
	echo 'www-user ALL=(daemon-user) SETENV: NOPASSWD: /usr/bin/git-http-backend, /usr/bin/hg' >> /etc/sudoers

RUN mkdir -p /var/log/supervisor && \
	a2enmod rewrite && \
	sed -i -e"s/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/my.cnf && \
	sed -i "s/\[mysqld\]/[mysqld]\n#\n# * Phabricator specific settings\n#\nsql_mode=STRICT_ALL_TABLES\nft_stopword_file=\/opt\/phabricator\/resources\/sql\/stopwords.txt\nft_min_word_len=3\ninnodb_buffer_pool_size=410M\nft_boolean_syntax=' \|-><()~*:\"\"\&\^'\n/" /etc/mysql/my.cnf && \
	sed -i 's/vcs:!:/vcs:NP:/' /etc/shadow && \
	sed -i 's/Port 22/Port 222/' /etc/ssh/sshd_config

RUN mkdir /usr/libexec && \
	echo '#!/bin/sh\nVCSUSER="vcs"\nROOT="/opt/phabricator"\nif [ "$1" != "$VCSUSER" ];\nthen\nexit 1\nfi\nexec "$ROOT/bin/ssh-auth" $@' > /usr/libexec/phabricator-ssh-hook.sh && \
	chown root /usr/libexec/phabricator-ssh-hook.sh && chmod 755 /usr/libexec/phabricator-ssh-hook.sh && \
	cp /opt/phabricator/resources/sshd/sshd_config.phabricator.example /etc/ssh/sshd_config.phabricator && \
	sed -i 's/vcs-user/vcs/' /etc/ssh/sshd_config.phabricator

RUN cd /opt/phabricator && ./bin/config set phd.user daemon-user && \
	./bin/config set diffusion.ssh-user vcs && \
	./bin/config set pygments.enabled true

RUN mkdir -p /var/repo/ && \
	ulimit -c 10000 && \
	apt-get clean && \
	rm -rf /var/lib/apt/lists/* && \
	ln -s /usr/lib/git-core/git-http-backend /usr/bin

ADD ./startup.sh /opt/startup.sh
ADD supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD phabricator.conf /etc/apache2/sites-available/phabricator.conf

RUN chmod +x /opt/startup.sh

RUN ln -s /etc/apache2/sites-available/phabricator.conf /etc/apache2/sites-enabled/phabricator.conf && \
	rm -f /etc/apache2/sites-enabled/000-default.conf

EXPOSE 80
EXPOSE 22
VOLUME ["/var/lib/mysql","/var/repo","/opt/phabricator/conf"]

CMD ["/usr/bin/supervisord"]

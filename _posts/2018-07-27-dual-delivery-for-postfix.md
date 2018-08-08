---
layout: blog
title: Dual Delivery setup for Postfix
topic: Mail Systems
type: Tutorials
categories: tutorials postfix
tags: tutorial, postfix, sysadmin, dual delivery, dual-delivery, postfix, mail, relay
date: 2018-07-27 21:30:00
banner: postfix-bg.svg
---

We recently decided to move one of our mail servers to GSuite. Now, we can't straight away update the MX records and say "Migration done!". We needed to make sure that no mails are dropped and so on. So, we decided not to start with MX update as soon as we created accounts for our users on GSuite. Our plan was to leave MX records as is for a while and keep forwarding a copy of every mail that our mail server receives to Google servers and eventually update the MX records. Now, after updating the MX records, we still had to keep our mail server alive so that any mail that reaches our server (due to cache) still get's delivered without bouncing back. The only difference is that we can choose to directly forward messages to Google servers without a dual delivery.

## Approach and Assumptions
For this setup, we need two mail servers. One is the mail server that has MX record poiting towards it (let's call this `students.iiit.ac.in`) and another mail server (let's call this `relay.students.iiit.ac.in`) that acts as realy to forward mails to Google. We needed a seperate relay (on a different ISP link) because, our primary link's bandwidth for mail servers was very limited and we didn't want to burn all our bandwidth whenever someone sends a mail to a mailing list (which happens very often). We can simply create a BCC mapping to all users/received mails on `students.iiit.ac.in` to `relay.iiit.ac.in`. That is, when a mail reaches our server for `user@students.iiit.ac.in`, we want to send a BCC to `user@relay.students.iiit.ac.in`. At the relay, we strip relay from the domain using domain masquerading and send it to Google servers.

## Preparing Mail server for Dual Delivery
### Add BCC Map
We first need to setup the BCC maps. We went with a list of users and their respective BCCs. The reason for this is, we had a lot of legacy forwardings, aliases on this server hence using some regex based map might end up sending multiple copies of the same mail.

First, create a file `/etc/postfix/bcc_map_to_relay`. The contents of this file should be similar to
{% highlight conf %}
user1:  user1@relay.students.iiit.ac.in
user2:  user2@relay.students.iiit.ac.in
user3:  user3@relay.students.iiit.ac.in
{% endhighlight %}

Once the file is ready, run

{% highlight shell %}
postmap /etc/postfix/bcc_map_to_relay
{% endhighlight %}

This will create a hashed DB file that will used by postfix. Now, change the following variable in the postfix configuration which is at `/etc/postfix/main.cf`

{% highlight conf %}
recipient_bcc_maps = hash:/etc/postfix/bcc_map_to_relay
{% endhighlight %}

To learn more about postfix BCC maps, you can refer the postfix documentation <a href="http://www.postfix.org/ADDRESS_REWRITING_README.html#auto_bcc" target="_blank">[refer]</a>.

Now, finally reload postfix to let it know the changes we made.
{% highlight shell %}
systemctl reload postfix
{% endhighlight %}

## Preparing Relay
### Install and setup Postfix
First, install postfix if you haven't.
{% highlight shell %}
yum install -y postfix
{% endhighlight %}

Now, change the following configuration variables in `/etc/postfix/main.cf`

{% highlight conf %}
myhostname = relay.students.iiit.ac.in
mydomain = students.iiit.ac.in
myorigin = $mydomain
inet_interfaces = localhost your_interface_ip
mydestination = $myhostname
masquerade_domains = students.iiit.ac.in
transport_maps =  hash:/etc/postfix/transport
alias_maps = hash:/etc/aliases, hash:/etc/postfix/user_maps

# Optional
mynetworks = 10.0.0.0/8, 127.0.0.1
{% endhighlight %}

### Domain Masquerading

The `masquerade_domains = students.iiit.ac.in` does our magic here. It essentially removes any prefix to `.students.iiit.ac.in` in the domain part. So, our `user1@relay.students.iiit.ac.in` becomes `user1@students.iiit.ac.in`. Next, we need to make sure that such user exists on this server or we can create aliases for the same. As I mentioned in the previous section, we can choose a regex based method to map all `@relay.students.iiit.ac.in` to `@students.iiit.ac.in`. We had a list of users anyway, so we went with adding alias for individual users.

To learn more about domain masquerading, you can refer postfix documentation <a href="http://www.postfix.org/ADDRESS_REWRITING_README.html#masquerade">[refer]</a>.

### Creating Aliases for users

Create a file `/etc/postfix/user_maps` with the contents similar to
{% highlight conf %}
user1@relay.students.iiit.ac.in    user1@students.iiit.ac.in
user2@relay.students.iiit.ac.in    user2@students.iiit.ac.in
user3@relay.students.iiit.ac.in    user3@students.iiit.ac.in
user4@relay.students.iiit.ac.in    user4@students.iiit.ac.in
{% endhighlight %}
We need to create a hash DB file for postfix. For this, run
{% highlight shell %}
postalias /etc/postfix/user_maps
{% endhighlight %}

### Defining Transport Map

Now, the last part is to redirect every mail that is intended for `students.iiit.ac.in` to our secondary mail server (which is Google in our case). For this, add the following to `/etc/postfix/transport`
{% highlight conf %}
students.iiit.ac.in     smtp:aspmx.l.google.com
{% endhighlight %}

This will send all mails headed for `students.iiit.ac.in` to `aspmx.l.google.com`. To learn more about transport, you can refer postfix documentation <a href="http://www.postfix.org/ADDRESS_REWRITING_README.html#transport" target="_blank">[refer]</a>.

We need to create a hash DB file for postfix. For this, run
{% highlight shell %}
postmap /etc/postfix/transport
{% endhighlight %}

Finally reload postfix to let it know the changes we made.
{% highlight shell %}
systemctl reload postfix
{% endhighlight %}

You are done! This setup will make sure that all the mails that reach the local server also reach Google servers. You can extended this to beyond two deliveries by adding more BCCs. But beware that tampering with BCCs needs you whitelist your relay server IPs at the secondary mail server (the server to which relay sends mails to).
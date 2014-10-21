# This is a basic VCL configuration file for varnish.  See the vcl(7)
# man page for details on VCL syntax and semantics.

backend smarthistory {
    .host = "khan.smarthistory.org";
    .port = "80";
}

backend ka {
    .host = "www.khanacademy.org";
    .port = "80";
}

backend appspot {
    .host = "khan-academy.appspot.com";
    .port = "80";
}

backend cs_scratchpad_audio_s3 {
    .host = "ka-cs-scratchpad-audio.s3.amazonaws.com";
    .port = "80";
}

sub vcl_recv {
    if (req.url ~ "\?(.*&)?clearcache([=&].*)?$") {
        ban("req.url ~ /");
    }

    unset req.http.Cookie;

    if (req.http.Host == "smarthistory.khanacademy.org") {
        set req.http.Host = "khan.smarthistory.org";
        set req.backend = smarthistory;

        if (req.url == "/robots.txt") {
            # We return a 600 HTTP "status code" which gets caught in the
            # vcl_error subroutine in order to serve a different robots.txt
            # file for smarthistory.khanacademy.org than for
            # khan.smarthistory.org. See http://serverfault.com/a/371781 for
            # more details on the technique.
            error 600 "OK";
        }
    } else if (req.http.Host ~ "(?:^|\.)kasandbox\.org$" && req.url ~ "^/s3/ka-cs-scratchpad-audio.*") {
        # We want the first to proxy to the second
        # http://kasandbox.org/s3/ka-cs-scratchpad-audio/71/a002f80db7cd1eb52277b85194348c/blob.mp3
        # https://ka-cs-scratchpad-audio.s3.amazonaws.com/71/a002f80db7cd1eb52277b85194348c/blob.mp3
        set req.http.Host = "ka-cs-scratchpad-audio.s3.amazonaws.com";
        set req.backend = cs_scratchpad_audio_s3;
        set req.url = regsub(req.url, "/s3/ka-cs-scratchpad-audio", "");
        
    } else if (req.http.Host ~ "(?:^|\.)kasandbox\.org$") {
        if (req.url ~ "(\?|&)host=([a-zA-Z0-9-_.]*)") {
            # We want to make it possible for kasandbox.org requests to get
            # proxied to the correct version/module of the site.  In order to do
            # this, we have the client pass a host parameter, which might be a
            # user-facing site like es.khanacademy.org (to ensure that the
            # request gets proxied to the i18n module) or a dev version like
            # staging.khan-academy.appspot.com (so that we can test the
            # kasandbox.org setup), and then proxy through to that host.
            #
            # As of June 2014, GAE routes requests based on the HTTP Host
            # header, as long as the request was sent to *.khanacademy.org if
            # the Host is *.khanacademy.org and likewise for *.appspot.com.  So
            # rather than trying to actually send the request to the requested
            # host, we just send it to www.khanacademy.org or
            # khan-academy.appspot.com, and set the HTTP Host header to
            # whatever the client requested.  This way, we don't have to try to
            # get Varnish to let us set an arbitrary backend hostname, which
            # seems to be hard or impossible.  It is also potentially more
            # secure since we will never actually send a request to anything
            # other than a fixed list of hosts (namely, the backends defined at
            # the top of this file).
            set req.http.Host = regsub(req.url, ".*(\?|&)host=([a-zA-Z0-9-_.]*)(&.*|$)", "\2");
            if (req.http.Host ~ "(^|\.)khanacademy\.org$") {
                set req.backend = ka;
            } else if (req.http.Host ~ "(^|\.|-dot-)khan-academy\.appspot\.com$") {
                # GAE *does* distinguish between appspot.com and
                # khanacademy.org URLs, and will 404 if the Host uses one but
                # the request is sent to the other, so if the user (in this
                # case probably a dev) asked for *.khan-academy.appspot.com,
                # send them there instead.
                set req.backend = appspot;
            } else {
                # If the host is neither *.khanacademy.org nor
                # *.khan-academy.appspot.com, someone is probably trying to do
                # something sketchy, so to be safe, let's redirect them to
                # www.khanacademy.org.
                set req.http.Host = "www.khanacademy.org";
                set req.backend = ka;
            }
        } else {
            # Otherwise we extract the host from the sub-domain
            if (req.http.Host ~ "^(?:www\.)?kasandbox\.org$") {
                # If no host is specified then we default to khanacademy.org
                set req.http.Host = "www.khanacademy.org";
                set req.backend = ka;
            } else if (req.http.Host ~ "^([a-zA-Z0-9-_.]*)\.kasandbox\.org$") {
                # If a host is specified then we point to the appspot
                # domain and set an appropriate host
                set req.http.Host = regsub(req.http.Host, "^([a-zA-Z0-9-_.]*)\.kasandbox\.org$", "\1-dot-khan-academy.appspot.com");
                set req.backend = appspot;
            }
        }

        # We unset User-Agent so that our ssl_for_spdy decorator doesn't
        # redirect to HTTPS, which Varnish would subsequently cache.
        unset req.http.User-Agent;

        # Check URL whitelist
        if (!req.url ~ "^/(?:cs|computer-programming)/exec($|\?)|^/(?:cs|computer-programming)/csp_reporter($|\?)|^(/genfiles/translations/[^/]*)?/javascript|^/stylesheets|^(/genfiles/translations/[^/]*)?/third_party/javascript-khansrc") {
            error 403 "Forbidden";
        }
    }
}

sub vcl_fetch {
    if (req.backend == smarthistory) {
        if (beresp.http.Content-Type ~ "^(?:image|audio|video)/") {
            # 28 days
            set beresp.ttl = 2419200s;
            set beresp.http.Cache-Control = "public, max-age=2419200";
        } else {
            # 1 day
            set beresp.ttl = 86400s;
            set beresp.http.Cache-Control = "public, max-age=86400";
        }
    }

    # Ignore all cookies
    unset beresp.http.Set-Cookie;
}

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }
}

sub vcl_error {
    if (obj.status == 600) {
        # Serve the robots.txt file. See vcl_recv above for more info.
        set obj.status = 200;
        set obj.http.Content-Type = "text/plain; charset=utf-8";
        synthetic {"User-agent: *
Disallow:"};
        return (deliver);
    }
}

# Below is a commented-out copy of the default VCL logic.  If you
# redefine any of these subroutines, the built-in logic will be
# appended to your code.
# sub vcl_recv {
#     if (req.restarts == 0) {
# 	if (req.http.x-forwarded-for) {
# 	    set req.http.X-Forwarded-For =
# 		req.http.X-Forwarded-For + ", " + client.ip;
# 	} else {
# 	    set req.http.X-Forwarded-For = client.ip;
# 	}
#     }
#     if (req.request != "GET" &&
#       req.request != "HEAD" &&
#       req.request != "PUT" &&
#       req.request != "POST" &&
#       req.request != "TRACE" &&
#       req.request != "OPTIONS" &&
#       req.request != "DELETE") {
#         /* Non-RFC2616 or CONNECT which is weird. */
#         return (pipe);
#     }
#     if (req.request != "GET" && req.request != "HEAD") {
#         /* We only deal with GET and HEAD by default */
#         return (pass);
#     }
#     if (req.http.Authorization || req.http.Cookie) {
#         /* Not cacheable by default */
#         return (pass);
#     }
#     return (lookup);
# }
# 
# sub vcl_pipe {
#     # Note that only the first request to the backend will have
#     # X-Forwarded-For set.  If you use X-Forwarded-For and want to
#     # have it set for all requests, make sure to have:
#     # set bereq.http.connection = "close";
#     # here.  It is not set by default as it might break some broken web
#     # applications, like IIS with NTLM authentication.
#     return (pipe);
# }
# 
# sub vcl_pass {
#     return (pass);
# }
# 
# sub vcl_hash {
#     hash_data(req.url);
#     if (req.http.host) {
#         hash_data(req.http.host);
#     } else {
#         hash_data(server.ip);
#     }
#     return (hash);
# }
# 
# sub vcl_hit {
#     return (deliver);
# }
# 
# sub vcl_miss {
#     return (fetch);
# }
# 
# sub vcl_fetch {
#     if (beresp.ttl <= 0s ||
#         beresp.http.Set-Cookie ||
#         beresp.http.Vary == "*") {
# 		/*
# 		 * Mark as "Hit-For-Pass" for the next 2 minutes
# 		 */
# 		set beresp.ttl = 120 s;
# 		return (hit_for_pass);
#     }
#     return (deliver);
# }
# 
# sub vcl_deliver {
#     return (deliver);
# }
# 
# sub vcl_error {
#     set obj.http.Content-Type = "text/html; charset=utf-8";
#     set obj.http.Retry-After = "5";
#     synthetic {"
# <?xml version="1.0" encoding="utf-8"?>
# <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
#  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
# <html>
#   <head>
#     <title>"} + obj.status + " " + obj.response + {"</title>
#   </head>
#   <body>
#     <h1>Error "} + obj.status + " " + obj.response + {"</h1>
#     <p>"} + obj.response + {"</p>
#     <h3>Guru Meditation:</h3>
#     <p>XID: "} + req.xid + {"</p>
#     <hr>
#     <p>Varnish cache server</p>
#   </body>
# </html>
# "};
#     return (deliver);
# }
# 
# sub vcl_init {
# 	return (ok);
# }
# 
# sub vcl_fini {
# 	return (ok);
# }

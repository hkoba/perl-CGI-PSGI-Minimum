[![Actions Status](https://github.com/hkoba/perl-CGI-PSGI-Minimum/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/hkoba/perl-CGI-PSGI-Minimum/actions?workflow=test)
# NAME

CGI::PSGI::Minimum - Run CGI.pm style application code on PSGI, with a small CGI.pm compatible object

# SYNOPSIS

    # app.psgi
    use CGI::PSGI::Minimum [as => 'CGI'];   # CGI->new means CGI::PSGI::Minimum->new
    use SelectSaver;

    my $app = sub {
      my $env = shift;
      my $cgi = CGI->new($env);
      {
        # Plain print goes to $cgi (the response body) while selected.
        my $saver = SelectSaver->new($cgi);
        MyApp->dispatch($cgi);
      }
      $cgi->psgi_tuple;   # [$status, \@headers, [$body]]
    };

    # MyApp.pm -- application code written for CGI.pm keeps working
    sub cmd_main {
      my ($self, $cgi) = @_;
      print $cgi->header(-type => 'text/html', -charset => 'utf-8');
      print "<h1>Hello, ", escape($cgi->param('name')), "</h1>\n";
    }

    sub cmd_update {
      my ($self, $cgi) = @_;
      ...
      print $cgi->redirect('./');
    }

    # A CGI/FastCGI driver can emit the same response in CGI style
    # after the application finished.
    print STDOUT $cgi->as_cgi_response;   # "Status: ...\r\n...\r\n\r\n" . body

# DESCRIPTION

CGI::PSGI::Minimum lets you run application code written against the
object interface of [CGI](https://metacpan.org/pod/CGI) (CGI.pm) on [PSGI](https://metacpan.org/pod/PSGI) servers, with as little
modification of the application code as possible.

It is **not** a subclass of CGI.pm and does not load it. It is a small,
independent reimplementation of the part of the CGI.pm API which real
world CGI applications use (parameters, URLs, cookies, request
information and response headers), built on [Plack::Request](https://metacpan.org/pod/Plack%3A%3ARequest). The object
is also a filehandle which collects the response body.

## The idea

A typical CGI.pm application prints its response from anywhere in the
code:

    print $cgi->header;
    print "<html>...";

With CGI::PSGI::Minimum:

- `header()` and `redirect()` do not return the header string.
They store the status and headers into the object and return `""`, so
`print $cgi->header(...)` prints nothing and keeps working.
- The object itself is a filehandle ([MOP4Import::Base::IOHandle](https://metacpan.org/pod/MOP4Import%3A%3ABase%3A%3AIOHandle))
which collects the body. `select` it (or `print $cgi ...`) and plain
`print` goes into the response body. Nothing is written to STDOUT.
- After the application finished, `psgi_tuple()` returns the PSGI
response `[$status, \@headers, [$body]]`. For CGI/FastCGI, the same
object can be serialized with `as_cgi_header()` / `as_cgi_response()`,
so one code base can serve both PSGI and CGI.

The modification needed in the application is usually limited to the
place where the object is created (`CGI->new` becomes
`CGI::PSGI::Minimum->new($env)`, or just `CGI->new($env)` with
`[as => 'CGI']`) and passing that object around instead of using
global state.

# GOALS, AND DIFFERENCES FROM CGI::PSGI

[CGI::PSGI](https://metacpan.org/pod/CGI%3A%3APSGI) ("Adapt CGI.pm to the PSGI protocol") and this module both
put a CGI.pm style object on top of a PSGI `$env`, and share method
names like `psgi_header()` and `psgi_redirect()`. But their goals are
different.

## CGI::PSGI: let frameworks use CGI.pm under PSGI

CGI::PSGI is meant for web **framework developers** who use CGI.pm to
handle query parameters and want their framework to speak PSGI. It
assumes that the framework already collects the response body in one
place, and asks that place to build the PSGI response by itself:

    my $q = CGI::PSGI->new($env);
    ...
    return [ $q->psgi_header, [ $body ] ];

- It **is** CGI.pm: a subclass of CGI (`use base qw(CGI)`). All of
CGI.pm's features are available, and its behavior is CGI.pm's behavior.
- To make CGI.pm (which reads `%ENV` and STDIN) work with
`$env`, it localizes `%ENV` to `$env` in `new` and in about 30 wrapped
methods, reads the request body from `psgi.input`, and resets CGI.pm's
globals with `CGI::initialize_globals()`.
- Application code that does `print $q->header` has to be
changed: `header()` still returns a string as in CGI.pm, and nothing
captures the output of `print`. For end users who want to run plain CGI
scripts, CGI::PSGI points to [CGI::Emulate::PSGI](https://metacpan.org/pod/CGI%3A%3AEmulate%3A%3APSGI) instead.

## CGI::PSGI::Minimum: keep CGI.pm style application code working

This module is meant for **application code** written against CGI.pm,
where `print $cgi->header` and `print "..."` are scattered all over
the code, and which you want to run on PSGI (and possibly still on
CGI/FastCGI) without rewriting it.

- The response is collected by the object, not by the caller:
`header()` / `redirect()` store into the object and return `""`, and
the body is printed into the object. The caller only returns
`$cgi->psgi_tuple`.
- It is **not** CGI.pm. It implements only a subset of the API, and
does not load CGI.pm at all. Where an argument is outside of the
supported subset, it croaks rather than silently doing something
different (ex. unknown options of `url()`).
- No global state: it does not touch `%ENV`, STDIN or STDOUT, and
has no per-process globals to reset (`_reset_globals` is a no-op). All
request information comes from `$env` passed to `new`. (Setting
`%ENV` from the accessors is possible with `[also_setenv]`, for legacy
code which reads `%ENV` directly.)
- Within the subset, CGI.pm compatibility of the **behavior** is the
goal, and is tested against CGI.pm itself where possible (ex. the header
string from `as_cgi_header()` is compared with CGI.pm's `header()`).
- The same object works for CGI/FastCGI drivers too, through
`as_cgi_header()`, `as_cgi_response()` and `reset_response()`.

## Which one to use

- You write or maintain a framework which already builds the
response body in one place, and want the full CGI.pm: use [CGI::PSGI](https://metacpan.org/pod/CGI%3A%3APSGI).
- You want to run an existing CGI script file as is, including its
use of `%ENV`, STDOUT and the function interface: use
[CGI::Emulate::PSGI](https://metacpan.org/pod/CGI%3A%3AEmulate%3A%3APSGI) (with [CGI::Compile](https://metacpan.org/pod/CGI%3A%3ACompile)), which emulates the CGI
environment for each request.
- You have application code using the CGI.pm object interface,
which prints from everywhere, and want it to run on PSGI without global
state and without depending on CGI.pm: use this module.

# IMPORT OPTIONS

Options are given as MOP4Import pragmas (array refs):

    use CGI::PSGI::Minimum [as => 'CGI'], [param_utf8];

- `[as => 'NAME']`

    Defines a constant `NAME` in the caller, which returns
    `"CGI::PSGI::Minimum"`. With `[as => 'CGI']`, `CGI->new($env)`
    creates a CGI::PSGI::Minimum object (CGI.pm is not loaded).

- `[param_utf8]`

    Equivalent of CGI.pm's `use CGI -utf8`: values retrieved by `param()`
    are decoded from UTF-8. Only values are decoded (not names); references,
    already decoded values and `PUTDATA`/`POSTDATA`/`PATCHDATA` are
    returned as is. This is a process wide setting (`$CGI::PSGI::Minimum::PARAM_UTF8`).

- `[also_setenv]`

    Makes the setter form of the request accessors (ex.
    `$cgi->request_method('POST')`) also set `%ENV`. Off by default.
    This is a process wide setting (`$CGI::PSGI::Minimum::ALSO_SETENV`).

Other package variables and environment variables:

- `$CGI::PSGI::Minimum::USE_PARAM_SEMICOLONS`

    When true (default, same as CGI.pm), `query_string()` joins pairs with
    `;`, otherwise with `&`.

- `WARN_CGI_GLOBAL_CALLS` (environment variable)

    When set at compile time, `_reset_globals()` warns when called. Useful
    to find code which relies on CGI.pm's global state.

# METHODS

## CONSTRUCTOR AND PSGI

### new

    my $cgi = CGI::PSGI::Minimum->new($env);

Creates an object for the PSGI environment `$env`. Unlike CGI.pm,
`$env` is required, and query strings or hashes of parameters are not
accepted.

### env

Returns the PSGI environment.

### request

Returns the [Plack::Request](https://metacpan.org/pod/Plack%3A%3ARequest) for `$env` (created once and cached). Use
it for what this module does not provide, ex. file uploads:
`$cgi->request->uploads`.

### psgi\_tuple

    return $cgi->psgi_tuple;   # [$status, \@headers, [$body]]

Returns the PSGI response built from the stored headers and the body
printed into the object. If `header()` / `redirect()` has not been
called, the status is 200 and the headers are empty.

### response

Returns a [Plack::Response](https://metacpan.org/pod/Plack%3A%3AResponse) with the stored status (default 200) and
headers. The body is not set.

### as\_bytes

Returns the body printed into the object so far (flushes first).

### Printing the body

The object is a filehandle. Either print to it explicitly, or `select`
it (ex. with [SelectSaver](https://metacpan.org/pod/SelectSaver)) so that plain `print` goes into it:

    print $cgi "text";
    binmode $cgi, ':encoding(utf8)';   # layers can be added as usual

## PARAMETERS

### param

    my @names = $cgi->param;            # names, in the original order
    my $value = $cgi->param('name');    # first value
    my @values = $cgi->param('name');   # all values
    $cgi->param('name', @values);       # set

Parameters from the query string and the request body
(`application/x-www-form-urlencoded` or `multipart/form-data`, query
string first) are merged. A POST request without `Content-Type` is
treated as urlencoded, as CGI.pm does. Like CGI.pm, the setter ignores
undef values, and leaves the parameter untouched when no defined value is
given. Only the positional form of the setter is supported (not
`-name => ..., -value => ...`). Uploaded files are not returned;
use `$cgi->request->uploads`.

### url\_param

    my @names = $cgi->url_param;
    my $value = $cgi->url_param('name');

Same as `param()`, but only for the query string.

### delete

    $cgi->delete('name');

### keywords

Returns the keywords of an `isindex` style query string (ex.
`?mary+had+a+little+lamb`).

### query\_string

Returns the parameters (including those set by `param()`) as a query
string. See `$USE_PARAM_SEMICOLONS`.

### parameters, query\_parameters

Returns the underlying ordered hashes ([Tie::IxHash](https://metacpan.org/pod/Tie%3A%3AIxHash)) of all parameters
and of the query string parameters. The values are array refs.

## URL AND REQUEST INFORMATION

### url

    $cgi->url;                         # http://host:port/cgi-bin/foo.cgi
    $cgi->url(-absolute => 1);         # /cgi-bin/foo.cgi
    $cgi->url(-relative => 1);         # foo.cgi
    $cgi->url(-path => 1, -query => 1);

Supported options are `-full` (default), `-absolute`, `-relative`,
`-path` (or `-path_info`) and `-query`. Other options croak.

### self\_url

Same as `url(-full => 1, -path => 1, -query => 1)`.

### http

    my $value = $cgi->http('Accept-Language');   # HTTP_ACCEPT_LANGUAGE
    my @names = $cgi->http;                      # HTTP_* keys (sorted)

Same as CGI.pm: the name is case insensitive, `-` is treated as `_`,
and the `HTTP_` prefix is optional (`http('User-Agent')`,
`http('user_agent')` and `http('HTTP_USER_AGENT')` are the same).

### protocol, virtual\_host, virtual\_port

Same as CGI.pm. `virtual_host` and `virtual_port` honor
`X-Forwarded-Host`.

### Request accessors

`auth_type`, `content_type`, `path_info`, `path_translated`,
`request_method`, `request_uri`, `remote_addr`, `remote_host`,
`remote_ident`, `remote_user`, `script_name`, `server_name`,
`server_port`, `server_protocol` and `server_software` return the
corresponding value of `$env`. With an argument, they set it (and also
`%ENV` with `[also_setenv]`).

`user_agent` and `referer` return `HTTP_USER_AGENT` and `HTTP_REFERER`.

## COOKIES

### cookie

    my @names = $cgi->cookie;                 # names of received cookies
    my $value = $cgi->cookie('name');         # value of a received cookie
    my $value = $cgi->cookie(-name => 'name');
    my $cookie = $cgi->cookie(-name => 'U', -value => '1000', -path => '/',
                              -expires => '+1d', -httponly => 1);
    print $cgi->header(-cookie => $cookie);

Like CGI.pm, without `-value` it is a getter of received cookies, and
with `-value` it creates a cookie object
(`CGI::PSGI::Minimum::Cookie`, serialized by [Cookie::Baker](https://metacpan.org/pod/Cookie%3A%3ABaker)), which
can be passed to `header(-cookie => ...)`. Supported attributes are
`-name`, `-value`, `-path`, `-domain`, `-expires`, `-max-age`,
`-secure`, `-httponly`, `-samesite` and `-priority`.

### raw\_cookie

    my $header = $cgi->raw_cookie;          # HTTP_COOKIE as is
    my $value  = $cgi->raw_cookie('name');  # URI escaped value

## RESPONSE HEADERS

### header

    $cgi->header;                                   # text/html; charset=ISO-8859-1
    $cgi->header('text/plain');                     # single argument is -type
    $cgi->header(-status => '400', -type => 'text/plain');
    $cgi->header(-type => 'application/pdf', '-Content-Length' => $size);
    $cgi->header(-cookie => [$cookie1, $cookie2], -expires => '+1h');

Unlike CGI.pm, `header()` does **not** return the header string. It stores
the response into the object and returns `""`, so that
`print $cgi->header(...)` works as is. The status code is stored in
`_status` (default 200), the headers in `_response_headers` (a flat
arrayref of name/value pairs), and the status string as given (ex.
`"302 Found"`) in `_status_text`. When called multiple times, the last
call wins.

Arguments are interpreted like CGI.pm's `header()`. Keys are normalized
(the leading `-` is removed, lowercased, `_` becomes `-`), so
`-Type`, `-type`, `-content_type` and `-Content-Type` are the same.
Known keys are `type` (`content-type`), `status`, `cookie`
(`cookies`, `set-cookie`), `target` (`window-target`), `expires`,
`nph` (accepted and ignored), `charset`, `attachment` and `p3p`
(`p3p-policy`). A single hash ref is also accepted.

Other `-name => value` pairs become arbitrary headers, named like
CGI.pm: `-X_Error_Reason` becomes `X-error-reason`. Keys without the
leading `-` are used as header names as is.

The headers are stored in the same order as CGI.pm outputs them:
`Window-Target`, `P3P`, `Set-Cookie` (one per cookie), `Expires`,
`Date` (when expires or cookie is given), `Pragma`,
`Content-Disposition`, arbitrary headers (in the argument order) and
`Content-Type` (omitted when `-type => ''`).

`charset` (default `ISO-8859-1`) is appended to `text/*` types only,
unless `-charset` is given explicitly or the type already has a charset.

`-expires` accepts the same forms as CGI.pm: `now`, `+30s`, `+10m`,
`+2h`, `-1d`, `+3M`, `+10y`, epoch seconds, or a preformatted date
string. The current time is taken from `_now()`, which can be overridden.

### psgi\_header

    my ($status, $headers) = $cgi->psgi_header(...);

Same as `header()`, but returns the stored status code and headers.

### redirect

    $cgi->redirect('http://example.com/');
    $cgi->redirect(-location => $url, -status => 301, -cookie => \@cookies,
                   'X-Foo' => 1);

Interprets arguments like CGI.pm's `redirect()`: `location` (`uri`,
`url`; defaults to `self_url`), `status` (default `"302 Found"`),
`target`, `cookie` and `nph`. Other arguments are passed to
`header()`. `Content-Type` is not emitted unless `-type` is given.
Returns `""`.

### psgi\_redirect

Same as `redirect()`, but returns `($status, $headers)`.

### charset

    $cgi->charset('utf-8');
    my $charset = $cgi->charset;

Gets or sets the default charset used by `header()` (default
`ISO-8859-1`, same as CGI.pm).

### cache

    $cgi->cache(1);
    $cgi->header;     # includes "Pragma: no-cache"

CGI.pm compatible. **Note that the meaning is inverted from what the name
suggests:** `cache(1)` (true) means "do NOT cache": `header()` emits
`Pragma: no-cache`. The name is misleading, but kept as is for CGI.pm
compatibility. By default (not set) no `Pragma` header is emitted.
Like CGI.pm, only a true value is stored (`cache(0)` does not reset it)
and the current value is always returned.

### has\_header

True if `header()` or `redirect()` has been called.

### as\_cgi\_header

Serializes the stored response into a CGI style header string, the same
form as CGI.pm's `header()` returns:

    Status: 302 Found\r\n
    Set-Cookie: U=1000; path=/\r\n
    Date: Tue, 14 Nov 2023 22:13:20 GMT\r\n
    Location: thanks.html\r\n
    \r\n

`Status` is emitted only when the status was specified explicitly (same
as CGI.pm). Returns `""` if `header()`/`redirect()` has not been called.
Intended for CGI/FastCGI drivers which emit headers after the application
finished, and for tests.

### as\_cgi\_response

`as_cgi_header() . as_bytes()`.

### reset\_response

    print $cgi $cgi->header, "partial output...";
    # an error occurred
    $cgi->reset_response;
    print $cgi $cgi->header(-status => 500), "error page";

Discards the response built so far, so that an error response can be
emitted instead of the partial one. After this, the object is in the same
state as a newly created one on which `header()` has not been called yet.
Returns the object itself.

It clears:

- the headers: `_status`, `_status_text`, `_response_headers` and
`_header_called`. `has_header` becomes false, `as_cgi_header` returns
`""`, and `psgi_tuple` / `response` return the same as a new object.
- the body printed to the object. The filehandle is not reopened:
it is flushed, rewound to the beginning, and the buffer is emptied. So
layers added by `binmode` (ex. `:encoding(utf8)`) are kept.

It does **not** clear the request side state (`env`, parameters, the
request object, cookies) nor the response settings (`charset`,
`encoding`, `cache`). `cache` is kept because it is a setting rather
than a part of the response: like CGI.pm, once set to true it can not be
reset (only a true value is stored), so clearing it here would silently
change that rule.

It is safe to call on an object without header or body, and any number of
times.

# HEADER INJECTION (HTTP RESPONSE SPLITTING, CWE-113)

Header values often contain user input (redirect targets, cookie values
...). A CR or LF in them would allow injecting arbitrary headers or body.
This module guards against it at two stages:

- When storing (header, redirect, psgi\_header, psgi\_redirect)

    Like CGI.pm, "CRLF + whitespace" (folding) in values is unfolded into the
    whitespace, and any other CR or LF makes it croak with
    `Invalid header value contains a newline not followed by whitespace`.
    NUL is rejected too, and header names must be RFC 9110 tokens. This
    applies to all values: type, status, cookies (after stringification),
    target, expires, charset, attachment, p3p, Location and arbitrary headers.
    Nothing is stored when it croaks.

- When serializing (as\_cgi\_header)

    Stored headers can be modified without going through `header()` (through
    the arrayref returned by `psgi_header()`, or directly through the
    object). So `as_cgi_header()` validates everything again just before
    output: names must be RFC 9110 tokens, values must not contain CR, LF or
    NUL (folding is not allowed here at all), the status must look like
    `302` or `302 Found`, and the headers must be an arrayref with an even
    number of elements. Any violation makes it croak (fail closed); invalid
    characters are never silently removed.

Error messages show control characters escaped (ex. `\x0D`), to avoid
log injection.

# NOT SUPPORTED

Being a minimum subset, the following parts of CGI.pm are not provided:

- The function interface (`use CGI qw(:standard)`, `param()`
without an object). Only the object interface is supported.
- HTML generation (`start_html`, `textfield`, ...) and sticky
forms.
- File uploads through `param()` / `upload()`. Use
`$cgi->request->uploads` ([Plack::Request::Upload](https://metacpan.org/pod/Plack%3A%3ARequest%3A%3AUpload)).
- `multi_param`, `Vars`, `append`, `save`, `restore_parameters`
and other less common methods.
- The named form of the `param()` setter, CGI.pm's positional
argument form of `header()` / `redirect()`, and NPH responses
(`-nph` is accepted and ignored).
- Creating an object without `$env` (from `%ENV`, a query string
or a hash of parameters).

Known intentional differences within the supported subset:

- `header()` / `redirect()` return `""` instead of the header
string. Use `psgi_header()`, `psgi_tuple()` or `as_cgi_header()`.
- The default charset is appended to `text/*` types only (CGI.pm
appends it to any type) unless `-charset` is given.
- Arbitrary headers keep the argument order (CGI.pm sorts them).
- Header values are validated more strictly (NUL, header names,
status format). See ["HEADER INJECTION (HTTP RESPONSE SPLITTING, CWE-113)"](#header-injection-http-response-splitting-cwe-113).

# SEE ALSO

[CGI](https://metacpan.org/pod/CGI), [CGI::PSGI](https://metacpan.org/pod/CGI%3A%3APSGI), [CGI::Emulate::PSGI](https://metacpan.org/pod/CGI%3A%3AEmulate%3A%3APSGI), [CGI::Compile](https://metacpan.org/pod/CGI%3A%3ACompile),
[Plack::Request](https://metacpan.org/pod/Plack%3A%3ARequest), [PSGI](https://metacpan.org/pod/PSGI), [MOP4Import::Base::IOHandle](https://metacpan.org/pod/MOP4Import%3A%3ABase%3A%3AIOHandle)

# LICENSE

Copyright (C) Kobayasi, Hiroaki.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Kobayasi, Hiroaki <buribullet@gmail.com>

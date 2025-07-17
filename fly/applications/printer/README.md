# PDF Appliance

This application enables you to offload your applications PDF generation requirements to an this application.  Key features:
  * Installs and runs Google Chrome headless.  Putting this into a second application keeps your applications image smaller, enabling quicker deployment.
  * Starts on demand.  Google Chrome is known to require considerable memory.  Instead of scaling your app's memory requirements to handle peak usage when PDFs are being generated, you can separately scale your app and this appliance.  The memory needed to run this appliance
  will only be allocated when you are generating PDFs.
  * Reuses the Google Chrome instance across multiple requests.  Starting Chrome can add a second or two to PDF generation.  By reusing an
  existing instance this can be avoided.  When combined with disabling JavaScript, achieving sub-second response times for generation of modest sized PDFs can be achieved.
  * Integrations with the authentication you already have.  Whether your authentication is session, cookie, or even HTTP basic auth, all the
  headers required will be passed through.

## [Installation](#installation)

* Clone this repository
* Use [`fly apps create`](https://fly.io/docs/flyctl/apps-create/) to create an application.  Generally we recommend that you take your existing application's name and add `-pdf` to the end of it, but you can call this whatever you want, and even use the `--generate-name` to let fly create one for you.
* Set the app name and primary region in the `fly.toml`.  Adjust the [environment](#environment) variables as needed.
* Run [`fly deploy`](https://fly.io/docs/flyctl/deploy/)
* Scale as needed.  See [scaling](#scaling) below.

## [Configure your environment](#environment)

* `HOSTNAME`: name of the host that this appliance will generate PDFs for.  Useful if you have a [custom domain](https://fly.io/docs/app-guides/custom-domains-with-fly/) or if you did not follow the recommendation to name your appliance app the same as your base application with a `-pdf` suffix.
* `PORT`: Port that the appliance listens to.  Must match the `internal_port` in your fly.toml.  Defaults to 3000.
* `TIMEOUT`: Number of minutes the appliance can remain idle before it is shutdown.
* `PAPERSIZE`: Puppeteer [PaperFormat](https://pptr.dev/api/puppeteer.paperformat).  Defaults to `letter`.
* `JAVASCRIPT`: Set to `false` to disable JavaScript.  If set to `false`, formatting will begin as soon as the page has [loaded](https://developer.mozilla.org/en-US/docs/Web/API/Window/load_event).  Otherwise, formatting will be delayed until the [`networkidle2`](https://pptr.dev/api/puppeteer.puppeteerlifecycleevent).

## [Integrate with your existing application](#integrate)

What you will need to do is to redirect requests using the [`Fly-Replay`](https://fly.io/docs/reference/dynamic-request-routing/#the-fly-replay-response-header) header for PDFs to the PDF appliance application.  The convention is that PDF versions of exiting pages can be produced by adding `.pdf` to the URL.

A few examples (in each, replace `appname-pdf` with the appliance application name you selected):

### [A single Rails controller action](#rails)

```ruby
def invoice
  if params[:format] == 'pdf'
    response.set_header 'Fly-Replay', 'app=appname-pdf'
    render :nothing, status: 307
    return
  end

  # render HTML version of your invoice
  . . .
end
```

You can link to such a PDF in a view using:

```ruby
<%= link_to "Invoice", invoice_people_path(format: :pdf) %>
```

### [An entire Node/Express application](#express)

```javascript
app.use((request, response, next) {
  let url = new URL(req.protocol + '://' + req.get('host') + req.originalUrl)

  if (url.pathname.endsWith('.pdf')) {
    response.set('Fly-Replay', 'app=appname-pdf')
    response.status(307)
    response.send()
  } else {
    next()
  }
})
```

### [NGINX application server](#nginx)

```nginx
# PDF generation
location ~ /.+\.pdf$ {
  add_header Fly-Replay app=appname-pdf;
  return 307;
}
```

## [Preloading (optional)](#preloading)

Cold starting a new machine, loading the Chrome headless application, and waiting for the appliance web server to accept request typically takes on the order of five seconds.  If your application can anticipate that a PDF is going to be requested, sending a HTTP request to the appliance can start that process before the user ever requests a PDF.  If the pathname in the HTTP request does not end with `.pdf`, the appliance will respond with a redirect to your application.

Either run this request in a separate thread for languages that support threading, or don't block on the response (e.g. by calling `await`) so as to not impede the flow of the application.

## [Scaling](#scaling)

Use [`fly scale`](https://fly.io/docs/flyctl/scale/) to adjust both the [count](https://fly.io/docs/apps/scale-count/) of the number of machines in each region you desire and [memory](https://fly.io/docs/flyctl/scale-memory/) for each machine.

Adjust [`http_service.concurency`](https://fly.io/docs/reference/configuration/#http_service-concurrency) in your `fly.toml` to limit the number of concurrent PDF generation requests being serviced by each machine.

## [Appendix: CSS](#css)

The following information may be useful to tailoring your CSS for printing:

* [Printing](https://developer.mozilla.org/en-US/docs/Web/Guide/Printing)
* [CSS paged media](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_paged_media)

Tailwind links:

* [Print modifier](https://tailwindcss.com/blog/tailwindcss-v3#print-modifier)
* [Break After](https://tailwindcss.com/docs/break-after)
* [Break Before](https://tailwindcss.com/docs/break-before)
* [Break Inside](https://tailwindcss.com/docs/break-inside)

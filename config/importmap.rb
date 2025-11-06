# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/channels", under: "channels"
pin_all_from "app/javascript/helpers", under: "helpers", preload: true
pin_all_from "app/javascript/components", under: "components"
pin "trix"
pin "@rails/actiontext", to: "actiontext.js"
pin "@xterm/xterm", to: "@xterm--xterm.js" # @5.5.0
pin "pdfjs-dist", to: "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.0.379/build/pdf.min.mjs"
pin "pdfjs-dist/build/pdf.worker.min.mjs", to: "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.0.379/build/pdf.worker.min.mjs"

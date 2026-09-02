(function () {

    const contentSelector = "#page-content";

    /*
     * Only these pages use seamless navigation.
     * The actual audio/player remains outside #page-content.
     */
    const seamlessPages = [
        "/",
        "/music",
        "/news"
    ];


    function isSeamlessLink(link) {

        if (!link) return false;

        if (link.target && link.target !== "_self") return false;

        if (link.hasAttribute("download")) return false;

        if (
            link.hasAttribute("data-no-pjax") ||
            link.hasAttribute("data-no-nav")
        ) {
            return false;
        }

        if (
            event &&
            (
                event.ctrlKey ||
                event.metaKey ||
                event.shiftKey ||
                event.altKey
            )
        ) {
            return false;
        }

        const url = new URL(link.href, window.location.href);

        if (url.origin !== window.location.origin) {
            return false;
        }

        return seamlessPages.includes(url.pathname);
    }


    async function loadPage(url, pushState) {

        const currentContent = document.querySelector(contentSelector);

        if (!currentContent) {
            window.location.href = url;
            return;
        }

        try {

            const response = await fetch(url, {
                method: "GET",
                headers: {
                    "X-ZimPlug-Navigation": "true"
                }
            });

            if (!response.ok) {
                throw new Error("Navigation failed: " + response.status);
            }

            const html = await response.text();

            const parser = new DOMParser();

            const documentHTML =
                parser.parseFromString(html, "text/html");

            const newContent =
                documentHTML.querySelector(contentSelector);

            if (!newContent) {
                throw new Error("Page content container not found.");
            }

            /*
             * IMPORTANT:
             *
             * We replace ONLY the page content.
             *
             * The <audio> element in base.html remains alive.
             *
             * Therefore playback does not stop.
             */
            currentContent.innerHTML = newContent.innerHTML;

            document.title = documentHTML.title;

            if (pushState) {
                history.pushState({}, "", url);
            }

            window.scrollTo({
                top: 0,
                behavior: "instant"
            });

            /*
             * Tell the player that the Music page changed.
             */
            window.dispatchEvent(
                new CustomEvent("zimplug:pagechange")
            );

        } catch (error) {

            console.error("ZimPlug navigation error:", error);

            /*
             * Safe fallback to normal navigation.
             */
            window.location.href = url;
        }
    }


    document.addEventListener("click", function (event) {

        const link = event.target.closest("a");

        if (!link) return;

        /*
         * Ignore modified clicks.
         */
        if (
            event.ctrlKey ||
            event.metaKey ||
            event.shiftKey ||
            event.altKey
        ) {
            return;
        }

        const url = new URL(link.href, window.location.href);

        if (!seamlessPages.includes(url.pathname)) {
            return;
        }

        if (url.origin !== window.location.origin) {
            return;
        }

        event.preventDefault();

        loadPage(url.href, true);
    });


    /*
     * Browser back/forward buttons.
     */
    window.addEventListener("popstate", function () {

        loadPage(window.location.href, false);
    });


})();

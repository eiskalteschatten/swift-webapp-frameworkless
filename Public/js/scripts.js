document.addEventListener("DOMContentLoaded", function () {
    document.getElementById("sayHelloButton").addEventListener("click", function () {
        const name = document.getElementById("name")?.value;
        window.location = `/hello/${name}`;
    });

    document.getElementById("sayHelloGermanButton").addEventListener("click", function () {
        const name = document.getElementById("name")?.value;
        window.location = `/hello/${name}?german=true`;
    });
});


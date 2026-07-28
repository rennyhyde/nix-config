(function () {
  'use strict';

  // ---------- Password gate ----------
  // Soft gate only — good enough to keep the guest list to invited people,
  // not real access control, so it's a plain comparison rather than routing
  // through SubtleCrypto (which can be missing or blocked in restricted
  // contexts like a `file://` page or a sandboxed embedded browser).
  //
  // Placeholder password for now: "sundrop2026"
  var PASSWORD = 'sundrop2026';

  var lockScreen = document.getElementById('lock-screen');
  var lockForm = document.getElementById('lock-form');
  var lockInput = document.getElementById('lock-password');
  var lockError = document.getElementById('lock-error');
  var siteContent = document.getElementById('site-content');

  function unlock() {
    lockScreen.remove();
    siteContent.hidden = false;
    try {
      sessionStorage.setItem('sundrop-unlocked', '1');
    } catch (e) {
      // sessionStorage unavailable (private browsing etc.) — not fatal, just
      // means the password is asked again on refresh.
    }
  }

  if (lockForm) {
    lockForm.addEventListener('submit', function (event) {
      event.preventDefault();
      var value = lockInput.value || '';

      if (value === PASSWORD) {
        unlock();
      } else {
        lockError.hidden = false;
        lockInput.value = '';
        lockInput.focus();
      }
    });
  }

  // Skip the lock screen on repeat visits within the same tab/session.
  try {
    if (sessionStorage.getItem('sundrop-unlocked') === '1' && lockScreen) {
      unlock();
    }
  } catch (e) {
    // ignore
  }

  // ---------- RSVP form ----------
  var rsvpForm = document.getElementById('rsvp-form');
  var rsvpStatus = document.getElementById('rsvp-status');

  function showStatus(message, ok) {
    rsvpStatus.textContent = message;
    rsvpStatus.hidden = false;
    rsvpStatus.className = 'rsvp-status ' + (ok ? 'ok' : 'err');
  }

  if (rsvpForm) {
    rsvpForm.addEventListener('submit', function (event) {
      event.preventDefault();

      var name = document.getElementById('rsvp-name').value.trim();
      var phone = document.getElementById('rsvp-phone').value.trim();
      var comingEl = rsvpForm.querySelector('input[name="coming"]:checked');
      var coming = comingEl ? comingEl.value : 'yes';

      if (!name || !phone) {
        showStatus('Please fill in your name and phone number.', false);
        return;
      }

      var submitBtn = rsvpForm.querySelector('button[type="submit"]');
      submitBtn.disabled = true;

      fetch('/api/rsvp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: name, phone: phone, coming: coming })
      })
        .then(function (res) {
          if (!res.ok) throw new Error('bad response');
          return res.json();
        })
        .then(function () {
          showStatus("Thanks — you're on the list!", true);
          rsvpForm.reset();
        })
        .catch(function () {
          showStatus('Something went wrong sending your RSVP. Please try again in a bit.', false);
        })
        .finally(function () {
          submitBtn.disabled = false;
        });
    });
  }
})();

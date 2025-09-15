+++
date = '2025-07-19T16:07:33+07:00'
draft = true
title = 'First Bounty a Memory to Keep'
+++
September 15th, 2020 was a day I’ll never forget.  
That was the day I received my very first bounty on HackerOne - $250 for a bug I almost overlooked: an **open redirect**.

At the time, I was digging into an integration feature in a web app, something that connected to third-party software. I initially thought it could lead to XSS or SSRF.  
I tried a bunch of payloads, spent hours testing and poking, but nothing worked.

I was close to giving up when I noticed something that seemed trivial: a redirect URL.  
After some deeper testing, I realized the **authentication token could be leaked via redirect to an external domain**. That’s when it clicked, even though it wasn’t XSS or SSRF, it was still a real issue.

So I submitted the report.  
A few days later, I received a reply:

> "Thank you for reporting this issue. We would like to award you with a bounty."

---

## What I Learned

- Sometimes the most impactful bugs come from the most unexpected places.
- Failure is part of the process. SSRF and XSS didn’t work, but that wasn’t the end.
- Bug bounty isn’t always about who’s the smartest, it’s often about who’s **persistent and curious enough to keep going**.

---

## A Note to Myself (and Anyone Starting Out)

This bug is a reminder that:  
**You don’t have to be an expert to find something meaningful. You just have to try, keep learning, and never give up.**

This first bounty wasn’t the finish line, it was just the beginning.  
It wasn’t just about the money, it was about validation. That I **can do this**, even without a background in IT.

So if you’re just getting started:  
**Keep looking. Keep learning. Keep failing. And keep going.**

Because sometimes, a small bug is all it takes to open a big door.

That's it, hope you enjoy. Thank you!

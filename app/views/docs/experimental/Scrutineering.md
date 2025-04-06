# Scrutineering

Scrutineering is a feature often found in larger competitions where
students register for multi-heats, are called back, and then are
ranked in successive semi-final rounds culminating in a final round.

The [rules for rankings are complex](https://www.dancepartner.com/articles/dancesport-skating-system.asp), but computers are good at that.
Rule 11, for example, can be tedious and error prone when done by hand, particularly when done under the time pressure of a live competition.
Having a computer be the scrutineer can produce instant results.

Current status is that the [code](https://github.com/rubys/showcase/blob/main/app/models/heat.rb#L75) for evaluating the rules is complete,
[tests](https://github.com/rubys/showcase/blob/main/test/models/heat_test.rb) are in place and pass,
but the configuration settings have not been exposed, the judging
forms have not been coded, and the display of results has yet to be created. In short, the hard part has been done, and I'm looking for
input on what the rest should look like.

Given that there are so many options, I'm looking for an event owner
who wants to try this out to specify the options that they want to use
and I'll implement those first.

DanceSport has a [tutorial](https://dancesport.org.au/accreditation/candidate_info/scrutineering_tutorial.pdf).  Page 12 shows an example user interface for ranking couples.
If that works, I can provide a similar interface.
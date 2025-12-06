# Scrutineering

Scrutineering is a feature commonly found in larger competitions where students register for multiple heats, are called back, and then ranked in successive semi-final rounds culminating in a final round.

The [rules for rankings are complex](./skating_system_algorithm.md), but computers excel at handling them. Rule 11, for example, can be tedious and error-prone when done by hand, especially under the time pressure of a live competition. Having a computer act as the scrutineer can produce instant results.

To enable scrutineering for a multi-heat, check the **Scrutineering?** button on that dance. When checked:

* All entries for this dance will be treated as a single heat, with semi-final rounds when needed. This means participants (particularly instructors) can only select one partner for this dance. If you want Newcomers not to be in the same heat as Gold, you can use [Competition Splits](../tasks/Multi-Dance#competition-splits-divisions) to divide competitors into separate divisions by level, age, or couple type.
* If a semi-final round is needed, judges will see checkboxes to select couples to be called back. They can change their selections, but cannot exceed the allotted number of callbacks.
* For final rounds, judges will see a list of couples in rank order. They can use drag and drop to reorder the list, which is initially shown in a random order for each judge.
* Results can be found by going to the Summary page and selecting **Multi-Scores**. Clicking on **All Scores** will show the rankings for each dance in the multi-dance. From there, clicking on **Calculations** shows how the final results were determined, including the application of skating rules to each heat and the overall placement. Clicking on **Callbacks** shows how callbacks were determined.

A few things to be aware of:

* The skating rules define a role of Chairman that makes several decisions. Over time, the plan is to make the Chairman's role highly configurable, allowing setup before and changes during an event. However, I want to avoid requiring complex configuration for basic use, so reasonable defaults are provided. The current defaults are:
    * If there are 8 or fewer couples in an event, no semi-final round is required.
    * If there are more than 8 couples, a single semi-final round precedes the final round.
    * In semi-final rounds, each judge is asked to call back 6 couples.
    * At most 8 couples will be called back. This means that 3 couples called back is possible, but 9 is not.
* If there are rules that can simplify things for everyone (for example, when to have multiple semi-finals or quarter-finals, and how many callbacks to assign), those will become the new defaults. If there are aspects that might reasonably differ (such as room size or limiting the maximum size of a semi-final round), those will be made configurable options.
* As with all new software, there may be bugs and missing features. If you spot a problem or have a request, let me know. Try the [demo](https://smooth.fly.dev/showcase/demo/) with textbook scenarios and see if the correct results are obtained. Feel free to share the demo link with colleagues—the demo is open to all.


# Troubleshooting Guide

This guide covers common problems and their solutions when using the showcase application.

## Getting Started Issues

### Cannot Access My Event
**Problem**: Can't log in or reach my event page

**Solutions**:

1. **Check your URL**: Ensure you're using the correct event-specific URL
2. **Password issues**: See [Passwords](./ops/Passwords) for reset instructions
3. **Browser compatibility**: Use a modern browser (Chrome, Firefox, Safari, Edge)
4. **Clear browser cache**: Try opening in an incognito/private window

### Missing Settings or Features
**Problem**: Can't find expected buttons or pages

**Solutions**:
1. **Check your role permissions**: Some features are only available to event organizers
2. **Refresh the page**: Some features load dynamically
3. **Check browser console**: Press F12 and look for JavaScript errors

## Entry Management Problems

### Cannot Add Entries
**Problem**: Entry form not saving or showing errors

**Solutions**:
1. **Verify required fields**: Ensure all required information is completed
2. **Check person records**: Both lead and follow must exist in the system
3. **Studio assignments**: Verify people are assigned to the correct studios
4. **Skill level matching**: Ensure skill levels are appropriate for the dance

### Entries Disappearing
**Problem**: Entries vanish after scheduling

**Solutions**:
1. **Check for orphaned entries**: Entries without valid heats are automatically removed
2. **Verify person relationships**: Ensure lead/follow assignments are still valid
3. **Review scratch status**: Entries may have been marked as scratched

### Billing Issues
**Problem**: Invoicing totals incorrect or missing entries

**Solutions**:
1. **Package configuration**: Verify packages are set up correctly before adding entries
2. **Studio vs student billing**: Check whether entries should be billed to studio or individual
3. **Regenerate invoices**: Changes to packages may require invoice regeneration

## Scheduling Problems

### "Cannot Create Valid Schedule"
**Problem**: Scheduler fails to generate heats

**Root Causes & Solutions**:
1. **Too many constraints**:
   - Enable age mixing (move age slider right)
   - Enable level mixing (move level slider right)
   - Allow open/closed mixing if appropriate
   
2. **Heat size limits too restrictive**:
   - Increase maximum couples per heat
   - Decrease minimum couples per heat
   - Check category-specific overrides

3. **Impossible conflicts**:
   - Look for instructors in too many entries at once
   - Check for circular studio conflicts
   - Verify all entries have valid dance assignments

### Schedule Takes Too Long
**Problem**: Event runs longer than desired

**Root Causes & Solutions**:
1. **Instructor bottleneck**: One person (often instructor) in too many entries
   - Reduce instructor's competition load
   - Consider splitting instructor entries across categories
   
2. **Settings too restrictive**:
   - Increase maximum couples per heat
   - Enable age/level mixing
   - Allow open/closed mixing
   
3. **Heat interval too long**:
   - Reduce time between consecutive heats
   - Typical range: 60-90 seconds

### Heats Too Small or Large
**Problem**: Heat sizes are uneven or inappropriate

**Solutions**:
1. **Adjust heat size settings**: Change minimum/maximum couples per heat
2. **Enable mixing**: Allow more flexibility in age/level combinations
3. **Check category overrides**: Individual categories may have different limits
4. **Review entry distribution**: Some combinations may naturally create small heats

## Scoring Issues

### Judges Cannot Log In
**Problem**: Judges can't access scoring system

**Solutions**:
1. **Verify judge setup**: Ensure judges are added to the system with correct information
2. **Check device compatibility**: Tablets and phones should work with modern browsers
3. **Network connectivity**: Verify Wi-Fi or cellular connection
4. **Browser issues**: Try different browsers or clear cache

### Scores Not Saving
**Problem**: Judge scores disappear or don't save

**Solutions**:
1. **Check internet connection**: Scores require active connection to save
2. **Refresh browser**: May resolve temporary connectivity issues
3. **Verify heat status**: Ensure you're scoring the correct, active heat
4. **Use paper backup**: Always have paper scoresheets as backup

### Missing Results
**Problem**: Results incomplete or showing incorrectly

**Solutions**:
1. **Verify all judges scored**: Check that every judge submitted scores for each heat
2. **Check scratch status**: Scratched entries won't appear in results
3. **Review calculation method**: Ensure correct scoring method is selected
4. **Regenerate results**: May need to recalculate after changes

## Audio and Media Issues

### Solo Music Not Playing
**Problem**: Uploaded music files won't play

**Solutions**:
1. **File format**: Use common formats (MP3, M4A, WAV)
2. **File size**: Large files may take time to upload/process
3. **Browser compatibility**: Some formats work better in different browsers
4. **Re-upload**: Try uploading the file again

### Counter Display Problems
**Problem**: Heat counter not updating or displaying incorrectly

**Solutions**:
1. **Refresh display**: Reload the counter page
2. **Check current heat**: Verify the correct heat is marked as current
3. **Browser compatibility**: Use a modern browser for display devices
4. **Network connection**: Display requires active internet connection

## Multi-Ballroom Issues

### Ballroom Assignment Problems
**Problem**: Heats assigned to wrong ballrooms or missing assignments

**Solutions**:
1. **Review ballroom settings**: Check [Ballrooms](./tasks/Ballrooms) configuration
2. **Regenerate schedule**: Re-run scheduling after ballroom changes
3. **Manual assignment**: Use drag-and-drop to reassign specific heats

## Performance Issues

### Slow Loading Pages
**Problem**: Application responds slowly

**Solutions**:
1. **Clear browser cache**: Old cached files may cause conflicts
2. **Check internet speed**: Slow connections affect performance
3. **Close other applications**: Free up device memory and processing power
4. **Use wired connection**: Ethernet is more reliable than Wi-Fi for critical operations

### Database Errors
**Problem**: Error messages about database issues

**Solutions**:
1. **Refresh the page**: Temporary issues often resolve automatically
2. **Check recent changes**: Undo recent modifications that may have caused conflicts
3. **Contact support**: Database errors may require technical assistance

## Event Day Emergencies

### Complete System Failure
**Problem**: Application becomes completely inaccessible

**Emergency Procedures**:
1. **Use paper backup**: Always have printed heat lists and scoresheets ready
2. **Mobile hotspot**: Try different internet connection
3. **Different device**: Switch to backup tablet/laptop
4. **Manual tracking**: Continue event with paper, enter scores later

### Power Outage
**Problem**: Loss of electricity during event

**Preparations**:
1. **Battery backups**: Ensure devices have charged batteries
2. **Mobile data**: Have cellular data as backup internet
3. **Printed materials**: Heat lists and emergency procedures on paper
4. **Manual scoring**: Paper scoresheets for all categories

### Judge Device Failure
**Problem**: Judge's tablet/device stops working

**Solutions**:
1. **Switch devices**: Move judge to backup device
2. **Paper scoring**: Use paper scoresheet for that judge
3. **Share device**: Have judges alternate on working devices
4. **Phone backup**: Judges can score using smartphones if needed

## Prevention Best Practices

### Before Your Event
- [ ] Test all technology 1-2 days before the event
- [ ] Have paper backups printed and ready
- [ ] Verify all team members can access their functions
- [ ] Test internet connectivity at venue
- [ ] Charge all devices and have power adapters ready

### During Your Event
- [ ] Monitor system performance regularly
- [ ] Keep backup devices charged and ready
- [ ] Have technical support contact information handy
- [ ] Stay calm and have backup plans ready

### Communication During Issues
1. **Stay calm**: Technical issues are solvable
2. **Communicate clearly**: Let participants know what's happening
3. **Use backup plans**: Switch to manual procedures if needed
4. **Document issues**: Note problems for future prevention

## Getting Additional Help

### Documentation Resources
- [Getting Started Guide](./Getting-Started) - Complete setup walkthrough
- [Scheduling Guide](./tasks/Scheduling) - Detailed scheduling help
- [Scoring Guide](./tasks/Scoring) - Comprehensive scoring instructions

### Support Contacts
- Technical support information is available in your event settings
- Many experienced organizers are willing to help newcomers
- Check the application's main page for current contact information

### Community Resources
- Connect with other event organizers who use the system
- Share experiences and solutions with the ballroom dance community
- Consider attending workshops or training sessions when available

## Remember
- Every problem has a solution
- Paper backups save the day
- Most issues are temporary and resolvable
- Preparation prevents most emergencies
- The show must go on - and it will!
import jenkins.model.*

/*
 * Create basic views and set their defaults.
 *
 * The ROS Build farm quickly suffers if the All view remains the default due
 * to the large number of packaging jobs. But Views are only created after the
 * configuration scripts are all run so they are not guaranteed to exist when
 * Jenkins starts.
 *
 * The Queue view is intentionally empty (intended to easily view all queued
 * jobs instead of only management jobs when the build queue filter is enabled)
 * Since it's empty by design, we can create it without any additional
 * knowledge and it can serve as a more reasonable default default than the All
 * view. If the Manage view already exists, we can set it as the default.
*/

j = Jenkins.get()
if (!j.getView("Queue")) {
	queue_view = new ListView("Queue")
	j.addView(queue_view)
	j.save()
}
if (j.getPrimaryView().name == "All") {
	manage_view = j.getView("Manage")
	if (manage_view) {
		j.setPrimaryView(manage_view)
	} else {
		j.setPrimaryView(j.getView("Queue"))
	}
	j.save()
}

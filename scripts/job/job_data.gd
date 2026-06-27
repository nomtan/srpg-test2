class_name JobData
extends Resource

var job_id: String
var job_name: String
var growth: Dictionary
var learnable_skills: Array[Dictionary] = []

static func create(id: String, display_name: String, values: Dictionary, skills: Array[Dictionary] = []) -> JobData:
	var job := JobData.new(); job.job_id = id; job.job_name = display_name; job.growth = values; job.learnable_skills = skills
	return job

.PHONY: clean data lint requirements sync_data_to_s3 sync_data_from_s3

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
BUCKET = [OPTIONAL] your-bucket-for-syncing-data (do not include 's3://')
PROFILE = default
PROJECT_NAME = netflix-movie-recommendation
PYTHON_INTERPRETER = python3

ifeq (,$(shell which conda))
HAS_CONDA=False
else
HAS_CONDA=True
endif

#################################################################################
# COMMANDS                                                                      #
#################################################################################

## Install or Update Python Dependencies
requirements: environment.lock

environment.lock: environment.yml
	conda env update -n $(PROJECT_NAME) -f $<
	conda env export -n $(PROJECT_NAME) | grep -v "prefix:" > $@

## Make Dataset
data: requirements data/processed/dataset.csv

## Split into train and test set
train_test_split: data/processed/dataset.csv
	$(PYTHON_INTERPRETER) src/models/train_model.py split $^ data/processed

## Train the models configured in model_config.py
train: train_test_split
	$(PYTHON_INTERPRETER) src/models/train_model.py train data/processed/train.csv models

## Evaluate the models on the test set
evaluate: models/report.json

## Delete all compiled Python files
clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete

# Delete raw data files
clean/raw:
	rm -rf data/raw


## Lint using flake8
lint:
	flake8 src

## Clean output of jupyter notebooks
clean_nb_%:
	jupyter nbconvert --ClearOutputPreprocessor.enabled=True --inplace notebooks/$*.ipynb

## Clean output of all jupyter notebooks
cleanall_nb: $(patsubst notebooks/%.ipynb,clean_nb_%,$(wildcard notebooks/*.ipynb))

## Upload Data to S3
sync_data_up:
ifeq (default,$(PROFILE))
	aws s3 sync data/ s3://$(BUCKET)/data/
else
	aws s3 sync data/ s3://$(BUCKET)/data/ --profile $(PROFILE)
endif

## Download Data from S3
sync_data_down:
ifeq (default,$(PROFILE))
	aws s3 sync s3://$(BUCKET)/data/ data/
else
	aws s3 sync s3://$(BUCKET)/data/ data/ --profile $(PROFILE)
endif

## Set up python interpreter environment
create_environment:
ifneq ("X$(wildcard ./environment.lock)","X")
	conda env create --name $(PROJECT_NAME) python=3.8 -f environment.lock
else
	@echo ">>> Creating lockfile from conda environment specification."
	conda env create --name $(PROJECT_NAME) python=3.8 -f environment.yml
	conda env export --name $(PROJECT_NAME) | grep -v "prefix:" > environment.lock
endif
	@echo ">>> New conda env created. Activate with: 'conda activate $(PROJECT_NAME)'"

delete_environment:
	@echo "Deleting conda environment."
	conda env remove -n $(PROJECT_NAME)
	
## Test python environment is setup correctly
test_environment:
	$(PYTHON_INTERPRETER) test_environment.py
	
#################################################################################
# PROJECT RULES                                                                 #
#################################################################################

## Fetch data into data/raw directory
data/raw:
	@echo "Fetching raw data..."
	rm -rf $@
	mkdir -p $@
	kaggle datasets download -d netflix-inc/netflix-prize-data
	mv netflix-prize-data.zip data/external
	unzip data/external/netflix-prize-data.zip -d data/raw

## Run generic processing and cleanup scripts to produce interim data
data/interim: data/raw
	@echo "Refining raw data..."
	mkdir -p $@
	$(PYTHON_INTERPRETER) src/data/generic_processing.py $^ $@

data/processed:
	mkdir -p $@

## Extract features and produce final dataset
data/processed/dataset.csv: data/interim | data/processed
	@echo "Producing dataset..."
	$(PYTHON_INTERPRETER) src/features/build_features.py $^ $|

models/report.json: train src/models/metric_config.py
	$(PYTHON_INTERPRETER) src/models/predict_model.py evaluate data/processed/test.csv models $@


#################################################################################
# Self Documenting Commands                                                     #
#################################################################################

.DEFAULT_GOAL := help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: help
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')

# INPUTFILES
INDIR=dl2
CRAB_FILE=$(INDIR)/crab.hdf5
GAMMA_FILE=$(INDIR)/gamma.hdf5
GAMMA_DIFFUSE_FILE=$(INDIR)/gamma_diffuse.hdf5
PROTON_FILE=$(INDIR)/proton.hdf5

# OUTPUT DIRECTORY
OUTDIR=build

# CONFIG FILES

REGRESSOR_CONFIG=configs/regressor.yaml
SEPARATOR_CONFIG=configs/separator.yaml
DISP_CONFIG=configs/disp.yaml

PREDICTION_THRESHOLD=0.85
THETA2_CUT=0.025

URL=https://factdata.app.tu-dortmund.de/dl2/FACT-Tools/v1.0.0


all: $(addprefix $(OUTDIR)/, \
	theta2_plot.pdf \
	) \
	$(addprefix $(OUTDIR)/, \
	gamma_application_done \
	) \
	$(addprefix $(OUTDIR)/, \
	)

dl2:
	mkdir -p dl2

# download the level 2 data files
dl2/gamma.hdf5: | dl2
	curl --fail -o dl2/gamma.hdf5 $(URL)/gamma_simulations_facttools_dl2.hdf5

dl2/gamma_diffuse.hdf5: | dl2
	curl --fail -o dl2/gamma_diffuse.hdf5 $(URL)/gamma_simulations_diffuse_facttools_dl2.hdf5

dl2/proton.hdf5: | dl2
	curl --fail -o dl2/proton.hdf5 $(URL)/proton_simulations_facttools_dl2.hdf5

dl2/crab.hdf5: | dl2
	curl --fail -o dl2/crab.hdf5 $(URL)/open_crab_sample_facttools_dl2.hdf5


# Apply precuts to the files
$(OUTDIR)/crab_precuts.hdf5: $(CRAB_FILE) configs/quality_cuts.yaml | $(OUTDIR)
	klaas_apply_cuts ./configs/quality_cuts.yaml \
		$(CRAB_FILE) \
		$(OUTDIR)/crab_precuts.hdf5 \
		-h h5py -k events --chunksize=10000

$(OUTDIR)/gamma_precuts.hdf5: $(GAMMA_FILE) configs/quality_cuts.yaml | $(OUTDIR)
	klaas_apply_cuts ./configs/quality_cuts.yaml \
		$(GAMMA_FILE) \
		$(OUTDIR)/gamma_precuts.hdf5 \
		-k events --chunksize=10000


$(OUTDIR)/gamma_diffuse_precuts.hdf5: $(GAMMA_DIFFUSE_FILE) configs/quality_cuts.yaml | $(OUTDIR)
	klaas_apply_cuts ./configs/quality_cuts.yaml \
		$(GAMMA_DIFFUSE_FILE) \
		$(OUTDIR)/gamma_diffuse_precuts.hdf5 \
		-k events --chunksize=10000

# Apply precuts to proton simulations
$(OUTDIR)/proton_precuts.hdf5: $(PROTON_FILE) configs/quality_cuts.yaml | $(OUTDIR)
	klaas_apply_cuts ./configs/quality_cuts.yaml \
		$(PROTON_FILE) \
		$(OUTDIR)/proton_precuts.hdf5 \
		-k events --chunksize=10000

# Split gamma data into
# * a training set for the separation
# * a training set for the energy regression
# * a set for the testing/deconvolution
$(OUTDIR)/gamma_train_sep.hdf5 $(OUTDIR)/gamma_train_reg.hdf5 $(OUTDIR)/gamma_test.hdf5: $(OUTDIR)/gamma_precuts.hdf5
	klaas_split_data $(OUTDIR)/gamma_precuts.hdf5 $(OUTDIR)/gamma \
		-f 0.2 -n train_sep \
		-f 0.2 -n train_reg \
		-f 0.6 -n test \
		-i events


# Split proton data into a training set for the separation and a test set
$(OUTDIR)/proton_train.hdf5 $(OUTDIR)/proton_test.hdf5: $(OUTDIR)/proton_precuts.hdf5
	klaas_split_data $(OUTDIR)/proton_precuts.hdf5 $(OUTDIR)/proton \
		-f 0.7 -n train \
		-f 0.3 -n test \
		-i events


$(OUTDIR)/separator.pkl $(OUTDIR)/separator_performance.hdf5: $(SEPARATOR_CONFIG) $(OUTDIR)/proton_train.hdf5 $(OUTDIR)/gamma_train_sep.hdf5
	klaas_train_separation_model \
		$(SEPARATOR_CONFIG) \
		$(OUTDIR)/gamma_train_sep.hdf5 \
		$(OUTDIR)/proton_train.hdf5 \
		$(OUTDIR)/separator_performance.hdf5 \
		$(OUTDIR)/separator.pkl \
		-k events

$(OUTDIR)/regressor.pkl $(OUTDIR)/regressor_performance.hdf5: $(REGRESSOR_CONFIG) $(OUTDIR)/gamma_train_reg.hdf5
	klaas_train_energy_regressor\
		$(REGRESSOR_CONFIG) \
		$(OUTDIR)/gamma_train_reg.hdf5 \
		$(OUTDIR)/regressor_performance.hdf5 \
		$(OUTDIR)/regressor.pkl \
		-k events

$(OUTDIR)/disp_model.pkl $(OUTDIR)/sign_model.pkl $(OUTDIR)/cv_disp.hdf5: ./$(DISP_CONFIG) $(OUTDIR)/gamma_diffuse_precuts.hdf5
	klaas_train_disp_regressor \
		$(DISP_CONFIG) \
		$(OUTDIR)/gamma_diffuse_precuts.hdf5 \
		$(OUTDIR)/cv_disp.hdf5 \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl \
		-k events


$(OUTDIR)/gamma_application_done: $(SEPARATOR_CONFIG) $(OUTDIR)/separator.pkl $(REGRESSOR_CONFIG) $(OUTDIR)/regressor.pkl $(DISP_CONFIG) $(OUTDIR)/disp_model.pkl $(OUTDIR)/sign_model.pkl | $(OUTDIR)/gamma_test.hdf5
	klaas_apply_energy_regressor $(REGRESSOR_CONFIG) \
		$(OUTDIR)/gamma_test.hdf5 \
		$(OUTDIR)/regressor.pkl \
		-k events  --yes --chunksize=100000

	klaas_apply_separation_model \
		$(SEPARATOR_CONFIG) \
		$(OUTDIR)/gamma_test.hdf5 \
		$(OUTDIR)/separator.pkl \
		-k events --chunksize=100000 --yes

	klaas_apply_disp_regressor $(DISP_CONFIG) \
		$(OUTDIR)/gamma_test.hdf5 \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl \
		-k events  --yes --chunksize=100000

	fact_calculate_theta $(OUTDIR)/gamma_test.hdf5 --yes --chunksize=300000

	touch $(OUTDIR)/gamma_application_done


$(OUTDIR)/crab_application_done: $(SEPARATOR_CONFIG) $(OUTDIR)/separator.pkl $(REGRESSOR_CONFIG) $(OUTDIR)/regressor.pkl $(DISP_CONFIG) $(OUTDIR)/disp_model.pkl $(OUTDIR)/sign_model.pkl | $(OUTDIR)/crab_precuts.hdf5
	klaas_apply_energy_regressor $(REGRESSOR_CONFIG) \
		$(OUTDIR)/crab_precuts.hdf5 \
		$(OUTDIR)/regressor.pkl \
		-k events  --yes --chunksize 100000

	klaas_apply_separation_model \
		$(SEPARATOR_CONFIG) \
		$(OUTDIR)/crab_precuts.hdf5 \
		$(OUTDIR)/separator.pkl \
		-k events --chunksize=100000 --yes

	klaas_apply_disp_regressor $(DISP_CONFIG) \
		$(OUTDIR)/crab_precuts.hdf5 \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl \
		-k events  --yes --chunksize=100000

	fact_calculate_theta $(OUTDIR)/crab_precuts.hdf5 --yes --source CRAB
	fact_calculate_radec $(OUTDIR)/crab_precuts.hdf5 --yes

	touch $(OUTDIR)/crab_application_done


$(OUTDIR)/crab_dl3.hdf5: scripts/to_dl3.py $(OUTDIR)/crab_application_done
	python scripts/to_dl3.py $(OUTDIR)/crab_precuts.hdf5 $(OUTDIR)/crab_dl3.hdf5

$(OUTDIR)/theta2_plot.pdf: $(OUTDIR)/crab_dl3.hdf5
	fact_plot_theta_squared \
		$(OUTDIR)/crab_dl3.hdf5 \
		--threshold=$(PREDICTION_THRESHOLD) \
		--theta2-cut=$(THETA2_CUT) \
		--preliminary \
		-o $(OUTDIR)/theta2_plot.pdf

$(OUTDIR):
	mkdir -p $(OUTDIR)

clean:
	rm -rf $(OUTDIR)


.PHONY: all clean crab_done

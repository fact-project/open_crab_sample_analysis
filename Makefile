URL=https://factdata.app.tu-dortmund.de/dl2/FACT-Tools/v1.1.2
INDIR=dl2
OUTDIR=build

CRAB_FILE=$(INDIR)/crab.hdf5
GAMMA_FILE=$(INDIR)/gamma.hdf5
GAMMA_DIFFUSE_FILE=$(INDIR)/gamma_diffuse.hdf5
PROTON_FILE=$(INDIR)/proton.hdf5

AICT_CONFIG=configs/aict.yaml

PREDICTION_THRESHOLD=0.8
THETA2_CUT=0.025


all: $(OUTDIR)/theta2_plot.pdf $(OUTDIR)/gamma_test_dl3.hdf5 $(OUTDIR)/crab_dl3.hdf5 $(OUTDIR)/proton_test_dl3.hdf5
all: $(OUTDIR)/separator_performance.pdf $(OUTDIR)/energy_performance.pdf $(OUTDIR)/disp_performance.pdf

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
	aict_apply_cuts ./configs/quality_cuts.yaml \
		$(CRAB_FILE) \
		$(OUTDIR)/crab_precuts.hdf5 \
		--chunksize=10000

$(OUTDIR)/gamma_precuts.hdf5: $(GAMMA_FILE) configs/quality_cuts.yaml | $(OUTDIR)
	aict_apply_cuts ./configs/quality_cuts.yaml \
		$(GAMMA_FILE) \
		$(OUTDIR)/gamma_precuts.hdf5 \
		--chunksize=10000


$(OUTDIR)/gamma_diffuse_precuts.hdf5: $(GAMMA_DIFFUSE_FILE) configs/quality_cuts.yaml | $(OUTDIR)
	aict_apply_cuts ./configs/quality_cuts.yaml \
		$(GAMMA_DIFFUSE_FILE) \
		$(OUTDIR)/gamma_diffuse_precuts.hdf5 \
		--chunksize=10000

# Apply precuts to proton simulations
$(OUTDIR)/proton_precuts.hdf5: $(PROTON_FILE) configs/quality_cuts.yaml | $(OUTDIR)
	aict_apply_cuts ./configs/quality_cuts.yaml \
		$(PROTON_FILE) \
		$(OUTDIR)/proton_precuts.hdf5 \
		--chunksize=10000

# Split gamma data into
# * a training set
# * a set for the testing/deconvolution
$(OUTDIR)/gamma_train.hdf5 $(OUTDIR)/gamma_test.hdf5: $(OUTDIR)/gamma_precuts.hdf5
	aict_split_data $(OUTDIR)/gamma_precuts.hdf5 $(OUTDIR)/gamma \
		-f 0.3 -n train \
		-f 0.7 -n test \
		-i events


# Split proton data into a training set for the separation and a test set
$(OUTDIR)/proton_train.hdf5 $(OUTDIR)/proton_test.hdf5: $(OUTDIR)/proton_precuts.hdf5
	aict_split_data $(OUTDIR)/proton_precuts.hdf5 $(OUTDIR)/proton \
		-f 0.7 -n train \
		-f 0.3 -n test \
		-i events


$(OUTDIR)/separator.pkl $(OUTDIR)/cv_separator.hdf5: $(AICT_CONFIG) $(OUTDIR)/proton_train.hdf5 $(OUTDIR)/gamma_diffuse_precuts.hdf5
	aict_train_separation_model \
		$(AICT_CONFIG) \
		$(OUTDIR)/gamma_diffuse_precuts.hdf5 \
		$(OUTDIR)/proton_train.hdf5 \
		$(OUTDIR)/cv_separator.hdf5 \
		$(OUTDIR)/separator.pkl

$(OUTDIR)/energy.pkl $(OUTDIR)/cv_energy.hdf5: $(AICT_CONFIG) $(OUTDIR)/gamma_train.hdf5
	aict_train_energy_regressor\
		$(AICT_CONFIG) \
		$(OUTDIR)/gamma_train.hdf5 \
		$(OUTDIR)/cv_energy.hdf5 \
		$(OUTDIR)/energy.pkl

$(OUTDIR)/disp_model.pkl $(OUTDIR)/sign_model.pkl $(OUTDIR)/cv_disp.hdf5: ./$(AICT_CONFIG) $(OUTDIR)/gamma_diffuse_precuts.hdf5
	aict_train_disp_regressor \
		$(AICT_CONFIG) \
		$(OUTDIR)/gamma_diffuse_precuts.hdf5 \
		$(OUTDIR)/cv_disp.hdf5 \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl


$(OUTDIR)/gamma_test_dl3.hdf5: $(AICT_CONFIG) $(OUTDIR)/separator.pkl $(OUTDIR)/energy.pkl
$(OUTDIR)/gamma_test_dl3.hdf5: $(OUTDIR)/disp_model.pkl $(OUTDIR)/sign_model.pkl $(OUTDIR)/gamma_test.hdf5
	fact_to_dl3 $(AICT_CONFIG) $(OUTDIR)/gamma_test.hdf5 \
		$(OUTDIR)/separator.pkl \
		$(OUTDIR)/energy.pkl \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl \
		$(OUTDIR)/gamma_test_dl3.hdf5 \
		--chunksize=100000 --yes


$(OUTDIR)/proton_test_dl3.hdf5: $(AICT_CONFIG) $(OUTDIR)/separator.pkl $(OUTDIR)/energy.pkl
$(OUTDIR)/proton_test_dl3.hdf5: $(OUTDIR)/disp_model.pkl $(OUTDIR)/sign_model.pkl $(OUTDIR)/proton_test.hdf5
	fact_to_dl3 $(AICT_CONFIG) $(OUTDIR)/proton_test.hdf5 \
		$(OUTDIR)/separator.pkl \
		$(OUTDIR)/energy.pkl \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl \
		$(OUTDIR)/proton_test_dl3.hdf5 \
		--chunksize=100000 --yes



$(OUTDIR)/crab_dl3.hdf5: $(AICT_CONFIG) $(OUTDIR)/separator.pkl $(OUTDIR)/energy.pkl
$(OUTDIR)/crab_dl3.hdf5: $(OUTDIR)/disp_model.pkl $(OUTDIR)/sign_model.pkl $(OUTDIR)/crab_precuts.hdf5
	fact_to_dl3 $(AICT_CONFIG) $(OUTDIR)/crab_precuts.hdf5 \
		$(OUTDIR)/separator.pkl \
		$(OUTDIR)/energy.pkl \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl \
		$(OUTDIR)/crab_dl3.hdf5 \
		--chunksize=100000 --yes


$(OUTDIR)/disp_performance.pdf: $(AICT_CONFIG) $(OUTDIR)/disp_model.pkl $(OUTDIR)/gamma_diffuse_precuts.hdf5
	aict_plot_disp_performance \
		$(AICT_CONFIG) \
		$(OUTDIR)/cv_disp.hdf5 \
		$(OUTDIR)/gamma_diffuse_precuts.hdf5 \
		$(OUTDIR)/disp_model.pkl \
		$(OUTDIR)/sign_model.pkl \
		-o $@


$(OUTDIR)/energy_performance.pdf: $(AICT_CONFIG) $(OUTDIR)/energy.pkl
	aict_plot_regressor_performance \
		$(AICT_CONFIG) \
		$(OUTDIR)/cv_energy.hdf5 \
		$(OUTDIR)/energy.pkl \
		-o $@


$(OUTDIR)/separator_performance.pdf: $(AICT_CONFIG) $(OUTDIR)/separator.pkl
	aict_plot_separator_performance \
		$(AICT_CONFIG) \
		$(OUTDIR)/cv_separator.hdf5 \
		$(OUTDIR)/separator.pkl \
		-o $@


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

resource "aws_ecr_repository" "multi_modal_app_image_repo" {
  name = "multi-modal-app-image-repo"
  // CF Property(EmptyOnDelete) = true
}